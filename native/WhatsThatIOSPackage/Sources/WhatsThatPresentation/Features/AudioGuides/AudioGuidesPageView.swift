import SwiftUI
import os
import WhatsThatShared
import WhatsThatDomain

/// Display mode for Audio Guides page (exposed to MainTabView for mini player visibility)
public enum AudioGuidesDisplayMode: Equatable {
    case hero
    case list
}

struct AudioGuidesPageView: View {
    @Environment(\.audioServices) private var audioServices
    @Environment(\.colorScheme) var colorScheme
    
    /// Binding to mode, so MainTabView can hide mini player in hero mode
    @Binding var mode: AudioGuidesDisplayMode
    
    /// Callback when user taps "Text" to open discovery detail
    let onTextSelected: (DiscoverySummary?) -> Void
    
    @StateObject private var viewModel: AudioGuidesViewModel
    @Namespace private var toggleNamespace
    @State private var overlayDragOffset: CGFloat = 0
    @State private var heroDragOffset: CGFloat = 0
    @State private var creditBalance: Int?
    
    // MARK: - Insufficient Credits State
    @State private var showInsufficientCreditsAlert: Bool = false
    @State private var presentedCreditsViewModel: CreditsViewModel?
    @State private var showCreditsSheet: Bool = false
    @State private var creditsSheetDetent: PresentationDetent = .fraction(0.8)
    private let makeCreditsViewModel: (() -> CreditsViewModel)?
    
    private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "AudioGuidesPageView")
    private let transitionDuration: Double = 0.3
    private let miniPlayerHeight: CGFloat = 76
    
    init(
        mode: Binding<AudioGuidesDisplayMode>,
        audioServices: AudioServicesContainer,
        onTextSelected: @escaping (DiscoverySummary?) -> Void = { _ in },
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil
    ) {
        self._mode = mode
        self.onTextSelected = onTextSelected
        self.makeCreditsViewModel = makeCreditsViewModel
        
        // Create ViewModel using passed audio services
        _viewModel = StateObject(wrappedValue: AudioGuidesViewModel(
            discoveryStore: audioServices.discoveryStore,
            queueStore: audioServices.queueStore,
            progressStore: audioServices.progressStore,
            speedStore: audioServices.speedStore,
            voiceoverController: audioServices.playbackController
        ))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            heroView
                .allowsHitTesting(mode == .hero)
            
            if mode == .list {
                listOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .background(BrandTheme.palette(for: colorScheme).background.ignoresSafeArea())
        .animation(.easeInOut(duration: transitionDuration), value: mode)
        .sheet(isPresented: $viewModel.showHistory) {
            HistorySheetView(
                viewModel: viewModel,
                audioServices: audioServices
            )
        }
        .alert(
            (creditBalance ?? 1) > 0 ? "Generate an audio guide?" : "You need credits to generate audio guides",
            isPresented: $viewModel.showCreateAlert,
            actions: {
                if (creditBalance ?? 1) > 0 {
                    Button("Cancel", role: .cancel) {
                        viewModel.discoveryForAlert = nil
                    }
                    Button("Generate") {
                        viewModel.confirmCreation()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now", role: .cancel) {
                        viewModel.discoveryForAlert = nil
                    }
                    Button("Get Credits") {
                        viewModel.discoveryForAlert = nil
                        presentCreditsSheet()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            },
            message: {
                if (creditBalance ?? 1) > 0 {
                    if let balance = creditBalance {
                        Text("This will use 1 credit. You have \(String(balance)) credits remaining.")
                    } else {
                        Text("This will use 1 credit.")
                    }
                } else {
                    Text("Each audio guide costs 1 credit. Purchase more to continue.")
                }
            }
        )
        .task {
            await viewModel.onAppear()
            // Fetch cached credit balance for the confirmation dialog
            if let store = audioServices?.creditBalanceStore {
                creditBalance = await store.getCached()
            }
        }
        // MARK: - Insufficient Credits Alert
        .alert(
            "Out of Credits",
            isPresented: $showInsufficientCreditsAlert,
            actions: {
                Button("Not Now", role: .cancel) { }
                Button("Get Credits") {
                    presentCreditsSheet()
                }
                .keyboardShortcut(.defaultAction)
            },
            message: {
                Text("Each audio guide costs 1 credit. Purchase more to continue.")
            }
        )
        // MARK: - Credits Sheet
        .sheet(isPresented: $showCreditsSheet, onDismiss: {
            presentedCreditsViewModel = nil
            creditsSheetDetent = .fraction(0.8)
        }) {
            NavigationStack {
                if let creditsViewModel = presentedCreditsViewModel {
                    CreditsView(viewModel: creditsViewModel)
                } else {
                    Text("Credits unavailable")
                        .font(.headline)
                        .padding()
                }
            }
            .presentationDetents([.fraction(0.8), .large], selection: $creditsSheetDetent)
            .presentationDragIndicator(.visible)
        }
        // MARK: - Observe assetStates for insufficient_credits errors
        .onChange(of: audioServices?.playbackController.assetStates) { _, newStates in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                guard let states = newStates else { return }
                for (_, asset) in states {
                    if asset.errorReason == "insufficient_credits" {
                        // Update local credit balance to 0 since server says no credits
                        creditBalance = 0
                        // Also update the store's cache
                        if let store = audioServices?.creditBalanceStore {
                            Task {
                                await store.set(0)
                            }
                        }
                        showInsufficientCreditsAlert = true
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Credits Sheet Helpers
    
    private func presentCreditsSheet() {
        guard let factory = makeCreditsViewModel else {
            log.warning("makeCreditsViewModel factory not available")
            return
        }
        let creditsViewModel = factory()
        presentedCreditsViewModel = creditsViewModel
        creditsSheetDetent = .fraction(0.8)
        showCreditsSheet = true
    }
}

// MARK: - Hero View

private extension AudioGuidesPageView {
    /// Fixed pill offset from safe area top - matches Discovery Detail's (resolvedTopPadding + 10) = (safeTop - 4 + 10) = safeTop + 6
    static let pillTopOffset: CGFloat = 6
    
    var heroView: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let screenHeight = proxy.size.height
            
            // Detect compact screens (iPad compatibility mode simulates ~568pt 4\" iPhone)
            let isCompactScreen = screenHeight < 600
            
            // Drag gesture to detect scroll-down intent (swipe up to reveal Up Next)
            let heroSwipeGesture = DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only track upward drags (negative y = swiping up)
                    if value.translation.height < 0 {
                        heroDragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    handleHeroSwipeEnd(translation: value.translation)
                }
            
            // Layout using VStack to naturally respect safe areas and push toggle bar to bottom
            VStack(spacing: 0) {
                // Main content area (flex)
                VStack(spacing: isCompactScreen ? 12 : 20) {
                    Spacer(minLength: isCompactScreen ? 8 : 12)
                    HeroPlayerView(isCompact: isCompactScreen, isCheckingVoiceoverStatus: viewModel.isLoadingVoiceoverStatus, hasAnyDiscoveries: !viewModel.localIds.isEmpty, onTextSelected: onTextSelected)
                        .padding(.horizontal, 16)
                    Spacer(minLength: isCompactScreen ? 8 : 12)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                
                // Toggle bar (pushed to bottom of safe area)
                toggleBar(enterListOnTap: true, showSelection: false)
                    .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace, isSource: mode == .hero)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6) // Small consistent gap above tab bar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // Ensure entire area is tappable for gesture
            .gesture(heroSwipeGesture)
            .ignoresSafeArea(edges: .top) // Let player content bleed into status bar area
            .overlay(alignment: .top) {
                // Pill (fixed position - matches Discovery Detail logic)
                HStack {
                    Spacer()
                    heroPill
                    Spacer()
                }
                .padding(.top, safeTop + Self.pillTopOffset)
                .ignoresSafeArea()
            }
        }
    }
    
    /// The pill for hero view - must match modeSwitcher styling
    private var heroPill: some View {
        HStack(spacing: 0) {
            Button(action: {
                guard let services = audioServices else { return }
                
                // First check if playback controller has a current discovery (most reliable)
                if let discovery = services.playbackController.currentDiscovery {
                    onTextSelected(discovery)
                    return
                }
                
                // Fallback: check queue store's current ID
                if let currentId = services.queueStore.current {
                    Task {
                        if let discovery = await services.discoveryStore.get(id: currentId) {
                            onTextSelected(discovery)
                        }
                    }
                }
            }) {
                Text("Text")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 80, height: 32)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
            }
            
            Button(action: {}) {
                Text("Audio")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 80, height: 32)
                    .foregroundColor(BrandColors.logo)
                    .background(
                        Capsule()
                            .fill(BrandTheme.palette(for: colorScheme).surface)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
            }
        }
        .padding(2)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - List Overlay

private extension AudioGuidesPageView {
    var listOverlay: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let dragGesture = DragGesture(minimumDistance: 12)
                .onChanged {
                    overlayDragOffset = max(0, $0.translation.height)
                }
                .onEnded {
                    handleOverlayDragEnd(translation: $0.translation)
                }
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 0) {
                    HStack {
                        Button(action: { exitListMode(reason: "down arrow") }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                                .padding(8)
                                .background(BrandTheme.palette(for: colorScheme).surface.opacity(0.9))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Close list")
                        .padding(.leading, 4)
                        
                        Spacer()
                        
                        // Top Toggles
                        listToggle
                    }
                    .padding(.top, topInset + 12)
                    .padding(.horizontal, 0)
                    
                    toggleBar(enterListOnTap: false, showSelection: true)
                        .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace, isSource: mode == .list)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                .gesture(dragGesture)
                
                // Content area
                ZStack {
                    if viewModel.selectedList == .upNext {
                        UpNextListView(
                            viewModel: viewModel,
                            audioServices: audioServices,
                            bottomPadding: 60,  // Extra space for View History button above mini player
                            onDismiss: { exitListMode(reason: "pull down from list") }
                        )
                    } else {
                        DiscoverListView(
                            viewModel: viewModel,
                            audioServices: audioServices,
                            bottomPadding: 60,  // Extra space for content above mini player
                            onDismiss: { exitListMode(reason: "pull down from list") }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                
                // Note: Mini player is now managed globally by MainTabView
                // No local mini player here
            }
            .padding(.horizontal, 0)
            .background(BrandTheme.palette(for: colorScheme).background)
            .ignoresSafeArea()
            .offset(y: overlayDragOffset)
            .animation(.easeInOut(duration: transitionDuration), value: overlayDragOffset)
        }
    }
    
    @ViewBuilder
    var listToggle: some View {
        if viewModel.selectedList == .upNext {
            HStack(spacing: 8) {
                Text("Autoplay")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                Toggle("", isOn: Binding(
                    get: { viewModel.autoplayEnabled },
                    set: { audioServices?.queueStore.autoplayEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: BrandColors.logo))
            }
            .padding(.trailing, 16)
        } else {
            HStack(spacing: 8) {
                Text("Show discoveries without audio")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $viewModel.showWithoutAudioGuide)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: BrandColors.logo))
            }
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Toggle Bar

private extension AudioGuidesPageView {
    func toggleBar(enterListOnTap: Bool, showSelection: Bool) -> some View {
        ToggleBarView(
            selectedList: $viewModel.selectedList,
            namespace: toggleNamespace,
            showSelection: showSelection
        ) { list in
            if list != .upNext {
                viewModel.resetHistoryLimit()
            }
            
            if enterListOnTap {
                enterListMode(selecting: list)
            }
        }
    }
    
    func enterListMode(selecting list: AudioGuideListType) {
        withAnimation(.easeInOut(duration: transitionDuration)) {
            viewModel.selectedList = list
            mode = .list
        }
    }
    
    func exitListMode(reason: String) {
        log.debug("Exiting list mode via \(reason, privacy: .public)")
        withAnimation(.easeInOut(duration: transitionDuration)) {
            mode = .hero
            overlayDragOffset = 0
            viewModel.resetHistoryLimit()
        }
    }
    
    func handleOverlayDragEnd(translation: CGSize) {
        let isDownward = translation.height > 80 && abs(translation.height) > abs(translation.width) * 1.2
        if isDownward {
            exitListMode(reason: "pull down")
        } else {
            withAnimation(.easeInOut(duration: transitionDuration)) {
                overlayDragOffset = 0
            }
        }
    }
    
    func handleHeroSwipeEnd(translation: CGSize) {
        // Detect upward swipe (negative height = swiping up, which means user wants to "scroll down" to see content below)
        let isUpward = translation.height < -50 && abs(translation.height) > abs(translation.width) * 1.2
        if isUpward {
            log.debug("Detected swipe-up gesture in hero mode, opening Up Next list")
            enterListMode(selecting: .upNext)
        }
        // Reset drag offset
        heroDragOffset = 0
    }
    
    func handleOpenPlayer(for discovery: DiscoverySummary) {
        viewModel.play(discovery: discovery)
        exitListMode(reason: "play from list")
        log.debug("Requested full player for discovery \(discovery.id, privacy: .public)")
    }
}

// MARK: - Toggle Bar View

struct ToggleBarView: View {
    @Binding var selectedList: AudioGuideListType
    let namespace: Namespace.ID
    let showSelection: Bool
    var onSelection: ((AudioGuideListType) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            toggleButton(title: "Up Next", type: .upNext)
            toggleButton(title: "My Discoveries", type: .discover)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .frame(height: 3)
                .foregroundColor(BrandTheme.palette(for: colorScheme).border),
            alignment: .bottom
        )
    }
    
    private func toggleButton(title: String, type: AudioGuideListType) -> some View {
        let isActive = showSelection && selectedList == type
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedList = type
            }
            onSelection?(type)
        }) {
            VStack(spacing: 4) {
                Text(title)
                    .fontWeight(isActive ? .bold : .medium)
                    .foregroundColor(isActive ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textSecondary)
                
                if isActive {
                    Capsule()
                        .fill(BrandColors.logo)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                } else {
                    Color.clear.frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Up Next List View

struct UpNextListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    let audioServices: AudioServicesContainer?
    var bottomPadding: CGFloat = 0
    var onDismiss: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var showClearQueueConfirmation = false
    
    // Scroll offset tracking for pull-down-to-dismiss
    @State private var baselineY: CGFloat? = nil
    @State private var hasDismissed = false
    private let dismissThreshold: CGFloat = 80
    
    var body: some View {
        List {

            
            // 1. Now Playing Section
            if let nowPlaying = viewModel.nowPlayingDiscovery {
                Section(header: Text("Now Playing").font(.caption).fontWeight(.bold)) {
                    nowPlayingRow(discovery: nowPlaying)
                }
            }
            
            // 2. Up Next Queue (includes queued items + base list fallback)
            Section(header: upNextSectionHeader) {
                upNextQueueRows
            }
            
            if viewModel.allUpNextItems.isEmpty && viewModel.nowPlayingDiscovery == nil {
                Text("Nothing queued — pick from Discover")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .padding(.top, 40)
            }
            
            // 3. Just Played (History)
            historySection
            
            Color.clear
                .frame(height: bottomPadding)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .miniPlayerScrollInset()
        .coordinateSpace(name: "upNextScrollContainer")
        .onPreferenceChange(AudioGuidesScrollOffsetPreferenceKey.self) { currentY in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                handleScrollChange(currentY: currentY)
            }
        }
    }
    
    private func handleScrollChange(currentY: CGFloat) {
        // Set baseline on first reading (when list is at rest)
        if baselineY == nil {
            baselineY = currentY
            return
        }
        
        guard let baseline = baselineY else { return }
        
        // Calculate overscroll: positive means user is pulling down past the top
        let overscroll = currentY - baseline
        
        // Trigger dismiss when pulled down beyond threshold
        if overscroll > dismissThreshold && !hasDismissed {
            hasDismissed = true
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onDismiss?()
        }
        
        // Reset dismiss flag when scroll returns to near baseline
        if overscroll <= 10 {
            hasDismissed = false
        }
    }
    
    @ViewBuilder
    private func nowPlayingRow(discovery: DiscoverySummary) -> some View {
        let state = viewModel.rowState(for: discovery.id)
        
        AudioGuideRowView(
            discovery: discovery,
            state: state,
            showMenu: false,
            onPlay: { /* Already playing */ },
            onOpenPlayer: { /* Already in hero */ }
        )
        // Force re-render when row states change
        .id("nowplaying-\(discovery.id)-\(viewModel.rowStateVersion)")
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12)
                .fill(BrandTheme.palette(for: colorScheme).surface)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        )
    }
    
    @ViewBuilder
    private var upNextSectionHeader: some View {
        let hasQueuedItems = !viewModel.upNextItems.isEmpty
        
        HStack {
            Text("Up Next")
                .font(.caption)
                .fontWeight(.bold)
            
            Spacer()
            
            // Clear Queue button - always visible, disabled when queue is empty
            Button(action: { showClearQueueConfirmation = true }) {
                Text("Clear Queue")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(hasQueuedItems ? .red.opacity(0.8) : BrandTheme.palette(for: colorScheme).textSecondary.opacity(0.4))
            }
            .disabled(!hasQueuedItems)
        }
        .alert("Clear Queue?", isPresented: $showClearQueueConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Queue", role: .destructive) {
                audioServices?.queueStore.clearQueue()
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        } message: {
            Text("This will remove all items you have manually added to your Up Next queue.")
        }
    }
    
    @ViewBuilder
    private var upNextQueueRows: some View {
        ForEach(viewModel.allUpNextItems, id: \.self) { discoveryId in
            UpNextRowContainer(
                discoveryId: discoveryId,
                viewModel: viewModel,
                audioServices: audioServices,
                onRemove: {
                    audioServices?.queueStore.remove(discoveryId)
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
    
    @ViewBuilder
    private var historySection: some View {
        if !viewModel.historyItems.isEmpty {
            Section(header: Text("Just Played").font(.caption).fontWeight(.bold)) {
                ForEach(viewModel.historyItems, id: \.self) { discoveryId in
                    HistoryRowContainer(
                        discoveryId: discoveryId,
                        viewModel: viewModel,
                        audioServices: audioServices
                    )
                    .opacity(0.6)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                
                if viewModel.historyItems.count < audioServices?.queueStore.history.count ?? 0 {
                    Button(action: {
                        withAnimation {
                            viewModel.loadMoreHistory()
                        }
                    }) {
                        Text(viewModel.historyLimit == 3 ? "View History" : "View More")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }
}

// MARK: - Up Next Row Container (Async Load)

private struct UpNextRowContainer: View {
    let discoveryId: Int64
    @ObservedObject var viewModel: AudioGuidesViewModel
    let audioServices: AudioServicesContainer?
    var onRemove: (() -> Void)?
    
    @State private var discovery: DiscoverySummary?
    
    var body: some View {
        Group {
            if let discovery {
                let state = viewModel.rowState(for: discovery.id)
                AudioGuideRowView(
                    discovery: discovery,
                    state: state,
                    showMenu: false,
                    onPlay: { viewModel.play(discovery: discovery) },
                    onOpenPlayer: { /* Handled by parent */ }
                )
                // Force re-render when row states change (ensures correct highlight state)
                .id("upnext-\(discovery.id)-\(viewModel.rowStateVersion)")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onRemove?()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            } else {
                ProgressView()
                    .tint(BrandColors.spinner)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .task {
            if let services = audioServices {
                discovery = await services.discoveryStore.get(id: discoveryId)
            }
        }
    }
}


// MARK: - History Row Container (Async Load)

private struct HistoryRowContainer: View {
    let discoveryId: Int64
    @ObservedObject var viewModel: AudioGuidesViewModel
    let audioServices: AudioServicesContainer?
    
    @State private var discovery: DiscoverySummary?
    
    var body: some View {
        Group {
            if let discovery {
                let state = viewModel.rowState(for: discovery.id)
                AudioGuideRowView(
                    discovery: discovery,
                    state: state,
                    showMenu: true,
                    onPlay: { viewModel.play(discovery: discovery) },
                    onOpenPlayer: { /* Handled by parent */ }
                ) {
                    Button {
                        viewModel.playNextInQueue(discovery.id)
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }
                    
                    Button {
                        viewModel.addToQueue(discovery.id)
                    } label: {
                        Label("Add to End", systemImage: "text.append")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        viewModel.addToQueue(discovery.id)
                    } label: {
                        Label("Queue", systemImage: "text.append")
                    }
                    .tint(BrandColors.logo)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .task {
            if let services = audioServices {
                discovery = await services.discoveryStore.get(id: discoveryId)
            }
        }
    }
}

// MARK: - Discover List View

struct DiscoverListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    let audioServices: AudioServicesContainer?
    var bottomPadding: CGFloat = 0
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        List {
            ForEach(groupedDiscoveries, id: \.0) { sectionTitle, sectionDiscoveries in
                Section(header: Text(sectionTitle).font(.caption).fontWeight(.bold)) {
                    ForEach(sectionDiscoveries, id: \.id) { discovery in
                        DiscoverRowContainer(
                            discovery: discovery,
                            viewModel: viewModel
                        )
                        // Force re-render when row states change (e.g., after triggering generation)
                        .id("discover-\(discovery.id)-\(viewModel.rowStateVersion)")
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(currentId: discovery.id)
                            }
                        }
                }
            }
        }
            
            if viewModel.isLoadingMore {
                 HStack(spacing: BrandSpacing.small) {
                     ProgressView()
                         .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.spinner))
                     Text("Loading more")
                         .font(.system(size: 14, weight: .semibold))
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.vertical, 12)
                 .listRowSeparator(.hidden)
                 .listRowBackground(Color.clear)
             }
            
            Color.clear
                .frame(height: bottomPadding)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .miniPlayerScrollInset()
        .onOverscrollDismiss {
            onDismiss?()
        }
    }
    
    private var groupedDiscoveries: [(String, [DiscoverySummary])] {
        viewModel.groupedDiscoveries(viewModel.filteredDiscoveries)
    }
}


// MARK: - Discover Row Container

private struct DiscoverRowContainer: View {
    let discovery: DiscoverySummary
    @ObservedObject var viewModel: AudioGuidesViewModel
    
    var body: some View {
        let state = viewModel.rowState(for: discovery.id)
        let isRecentlyQueued = viewModel.recentlyQueuedDiscoveryId == discovery.id
        
        AudioGuideRowView(
            discovery: discovery,
            state: state,
            showMenu: state.voiceoverStatus.isPlayable,
            isRecentlyQueued: isRecentlyQueued,
            onPlay: { viewModel.play(discovery: discovery) },
            onOpenPlayer: { /* Handled by parent */ },
            onCreate: { viewModel.requestCreation(for: discovery) }
        ) {
            if state.voiceoverStatus.isPlayable {
                Button {
                    viewModel.playNextInQueue(discovery.id)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                
                Button {
                    viewModel.addToQueue(discovery.id)
                } label: {
                    Label("Add to End", systemImage: "text.append")
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if state.voiceoverStatus.isPlayable {
                Button {
                    viewModel.addToQueue(discovery.id)
                } label: {
                    Label("Queue", systemImage: "text.append")
                }
                .tint(BrandColors.logo)
            }
        }
    }
}

// MARK: - Custom Alert View

struct CustomAlertView: View {
    let title: String
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onCancel() }
            
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 0.5)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
                .padding(16)
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .fontWeight(.regular)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    
                    Divider()
                        .frame(width: 0.5)
                        .background(Color.gray.opacity(0.3))
                    
                    Button(action: onConfirm) {
                        Text("Create")
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                }
                .frame(height: 44)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(width: 270)
        }
        .zIndex(999)
    }
}

// MARK: - History Sheet View

struct HistorySheetView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    let audioServices: AudioServicesContainer?
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    
    @State private var historyDiscoveries: [DiscoverySummary] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(historyDiscoveries, id: \.id) { discovery in
                    let state = viewModel.rowState(for: discovery.id)
                    AudioGuideRowView(
                        discovery: discovery,
                        state: state,
                        showMenu: false,
                        onPlay: { viewModel.play(discovery: discovery) },
                        onOpenPlayer: {
                            viewModel.play(discovery: discovery)
                            presentationMode.wrappedValue.dismiss()
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("History")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .task {
            await loadHistoryDiscoveries()
        }
    }
    
    private func loadHistoryDiscoveries() async {
        guard let services = audioServices else { return }
        let historyIds = services.queueStore.history
        
        var loaded: [DiscoverySummary] = []
        for id in historyIds {
            if let discovery = await services.discoveryStore.get(id: id) {
                loaded.append(discovery)
            }
        }
        historyDiscoveries = loaded
    }
}

// MARK: - Scroll Offset Tracking

/// PreferenceKey to track scroll offset from the top of a list (local to Audio Guides)
private struct AudioGuidesScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A view modifier that adds a scroll offset tracker to a list
/// When the user overscrolls at the top (pulls down while at top), it calls the onOverscroll callback
struct OverscrollDismissModifier: ViewModifier {
    let onDismiss: () -> Void
    let threshold: CGFloat
    
    @State private var isOverscrolling = false
    @State private var scrollOffset: CGFloat = 0
    
    init(threshold: CGFloat = 60, onDismiss: @escaping () -> Void) {
        self.threshold = threshold
        self.onDismiss = onDismiss
    }
    
    func body(content: Content) -> some View {
        content
            .onPreferenceChange(AudioGuidesScrollOffsetPreferenceKey.self) { topY in
                // Defer to next runloop to prevent "update multiple times per frame" error
                DispatchQueue.main.async {
                    // When the top of the list content is below its normal position (positive offset),
                    // it means the user is pulling down at the top
                    // We need to track the initial position and detect when it moves beyond threshold
                    handleScrollOffsetChange(topY: topY)
                }
            }
    }
    
    private func handleScrollOffsetChange(topY: CGFloat) {
        // Store the first value as the baseline
        if scrollOffset == 0 && topY > 0 {
            scrollOffset = topY
        }
        
        // Calculate how far below the baseline we are (overscroll amount)
        let overscrollAmount = topY - scrollOffset
        
        // If we've pulled down beyond the threshold and haven't triggered yet
        if overscrollAmount > threshold && !isOverscrolling {
            isOverscrolling = true
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onDismiss()
        } else if overscrollAmount <= 0 {
            // Reset when scroll returns to normal
            isOverscrolling = false
        }
    }
}

extension View {
    /// Adds pull-down-to-dismiss behavior when the list is at the top
    func onOverscrollDismiss(threshold: CGFloat = 60, perform action: @escaping () -> Void) -> some View {
        modifier(OverscrollDismissModifier(threshold: threshold, onDismiss: action))
    }
}
