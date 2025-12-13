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
    @State private var creditBalance: Int?
    
    private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "AudioGuidesPageView")
    private let transitionDuration: Double = 0.3
    private let miniPlayerHeight: CGFloat = 76
    
    init(
        mode: Binding<AudioGuidesDisplayMode>,
        audioServices: AudioServicesContainer,
        onTextSelected: @escaping (DiscoverySummary?) -> Void = { _ in }
    ) {
        self._mode = mode
        self.onTextSelected = onTextSelected
        
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
            BrandTheme.palette(for: colorScheme).background
                .ignoresSafeArea()
            
            heroView
                .allowsHitTesting(mode == .hero)
            
            if mode == .list {
                listOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: transitionDuration), value: mode)
        .sheet(isPresented: $viewModel.showHistory) {
            HistorySheetView(
                viewModel: viewModel,
                audioServices: audioServices
            )
        }
        .alert(
            "Generate an audio guide?",
            isPresented: $viewModel.showCreateAlert,
            actions: {
                Button("Cancel", role: .cancel) {
                    viewModel.discoveryForAlert = nil
                }
                Button("Generate") {
                    viewModel.confirmCreation()
                }
                .keyboardShortcut(.defaultAction)
            },
            message: {
                if let balance = creditBalance {
                    Text("This will use 1 credit. You have \(String(balance)) credits remaining.")
                } else {
                    Text("This will use 1 credit.")
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
    }
}

// MARK: - Hero View

private extension AudioGuidesPageView {
    /// Fixed pill offset from safe area top - matches Discovery Detail's (resolvedTopPadding + 10) = (safeTop - 4 + 10) = safeTop + 6
    static let pillTopOffset: CGFloat = 6
    
    var heroView: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            let safeTop = proxy.safeAreaInsets.top
            let reservedBottom: CGFloat = 52 + bottomInset
            
            ZStack(alignment: .bottom) {
                // Main content (flex layout)
                VStack(spacing: 20) {
                    Spacer(minLength: 12)
                    HeroPlayerView(onTextSelected: onTextSelected)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, reservedBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                
                // Toggle bar (fixed at bottom)
                toggleBar(enterListOnTap: true, showSelection: false)
                    .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace, isSource: mode == .hero)
                    .padding(.horizontal, 8)
                    .padding(.bottom, bottomInset)
            }
            .overlay(alignment: .top) {
                // Pill (fixed position - matches Discovery Detail logic)
                // Discovery Detail uses resolvedTopPadding (safeTop - 4) + 10
                HStack {
                    Spacer()
                    heroPill
                    Spacer()
                }
                .padding(.top, safeTop + Self.pillTopOffset)
                .ignoresSafeArea()
                .onAppear {
                    print("🔍 AudioGuides: safeTop = \(safeTop)")
                    print("🔍 AudioGuides: pillTopOffset = \(Self.pillTopOffset)")
                    print("🔍 AudioGuides: calculated = \(safeTop + Self.pillTopOffset)")
                }
            }
        }
    }
    
    /// The pill for hero view - must match modeSwitcher styling
    private var heroPill: some View {
        HStack(spacing: 0) {
            Button(action: {
                if let services = audioServices,
                   let currentId = services.queueStore.current {
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
                            bottomPadding: 60  // Extra space for View History button above mini player
                        )
                    } else {
                        DiscoverListView(
                            viewModel: viewModel,
                            audioServices: audioServices,
                            bottomPadding: 60  // Extra space for content above mini player
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
    @Environment(\.colorScheme) var colorScheme
    @State private var showClearQueueConfirmation = false
    
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
    
    @State private var discoveries: [DiscoverySummary] = []
    
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
                    }
                }
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
        .task {
            await loadDiscoveries()
        }
    }
    
    private var groupedDiscoveries: [(String, [DiscoverySummary])] {
        viewModel.groupedDiscoveries(filteredDiscoveries)
    }
    
    private var filteredDiscoveries: [DiscoverySummary] {
        if viewModel.showWithoutAudioGuide {
            return discoveries
        } else {
            return discoveries.filter { discovery in
                let state = viewModel.rowState(for: discovery.id)
                return state.voiceoverStatus.isPlayable
            }
        }
    }
    
    private func loadDiscoveries() async {
        guard let services = audioServices else { return }
        discoveries = await services.discoveryStore.allCached()
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
