import SwiftUI
import os
import WhatsThatShared

struct AudioGuidesPageView: View {
    enum ViewMode {
        case fullPage
        case list
    }

    @StateObject private var viewModel = AudioGuidesViewModel()
    @Environment(\.colorScheme) var colorScheme
    private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "AudioGuidesPageView")

    @State private var mode: ViewMode = .fullPage
    @Namespace private var toggleNamespace
    @State private var overlayDragOffset: CGFloat = 0

    private let transitionDuration: Double = 0.3
    private let miniPlayerHeight: CGFloat = 76

    var body: some View {
        ZStack(alignment: .bottom) {
            BrandTheme.palette(for: colorScheme).background
                .ignoresSafeArea()

            fullPageView
                .allowsHitTesting(mode == .fullPage)

            if mode == .list {
                listOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
            
            if viewModel.showCreateAlert {
                CustomAlertView(
                    title: "Generate an audio guide?",
                    message: "The audio guide takes one credit.\nYou currently have \(viewModel.userCredits) credits.",
                    onCancel: {
                        withAnimation {
                            viewModel.showCreateAlert = false
                            viewModel.guideForAlert = nil
                        }
                    },
                    onConfirm: {
                        withAnimation {
                            viewModel.confirmCreation()
                            viewModel.showCreateAlert = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: transitionDuration), value: mode)
    }
}

private extension AudioGuidesPageView {
    var fullPageView: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            let reservedBottom: CGFloat = 52 + bottomInset

            ZStack(alignment: .bottom) {
                VStack(spacing: 20) {
                    Spacer(minLength: 12)
                    HeroPlayerView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, reservedBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                toggleBar(enterListOnTap: true, showSelection: false)
                    .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace, isSource: mode == .fullPage)
                    .padding(.horizontal, 8)
                    .padding(.bottom, bottomInset)
            }
        }
    }

    var listOverlay: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let dragGesture = DragGesture(minimumDistance: 12)
                .onChanged { value in
                    overlayDragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    handleOverlayDragEnd(translation: value.translation)
                }

            VStack(spacing: 0) {
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
                        if viewModel.selectedList == .upNext {
                            HStack(spacing: 8) {
                                Text("Autoplay")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                                Toggle("", isOn: $viewModel.autoplayEnabled)
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
                    .padding(.top, topInset + 12)
                    .padding(.horizontal, 0)

                    toggleBar(enterListOnTap: false, showSelection: true)
                        .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace, isSource: mode == .list)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                .gesture(dragGesture)

                // Content area - specific list handles scrolling
                ZStack {
                    if viewModel.selectedList == .upNext {
                        UpNextListView(
                            viewModel: viewModel,
                            bottomPadding: bottomInset + miniPlayerHeight + 16
                        ) { guide in
                            handleOpenPlayer(for: guide)
                        }
                    } else {
                        DiscoverListView(
                            viewModel: viewModel,
                            bottomPadding: bottomInset + miniPlayerHeight + 16
                        ) { guide in
                            handleOpenPlayer(for: guide)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                MiniPlayerView(viewModel: viewModel) {
                    log.debug("Mini player tapped to close overlay")
                    exitListMode(reason: "mini player tap")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset + BrandSpacing.small)
            }
            .padding(.horizontal, 0)
            .background(BrandTheme.palette(for: colorScheme).background)
            .ignoresSafeArea()
            .offset(y: overlayDragOffset)
            .animation(.easeInOut(duration: transitionDuration), value: overlayDragOffset)
        }
    }

    func toggleBar(enterListOnTap: Bool, showSelection: Bool) -> some View {
        ToggleBarView(
            selectedList: $viewModel.selectedList,
            namespace: toggleNamespace,
            showSelection: showSelection
        ) { list in
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
            mode = .fullPage
            overlayDragOffset = 0
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

    func handleOpenPlayer(for guide: AudioGuide) {
        viewModel.playGuide(guide)
        log.debug("Requested full player for guide \(guide.id.uuidString, privacy: .public)")
    }
}

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

struct UpNextListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    var bottomPadding: CGFloat = 0
    var onOpenPlayer: (AudioGuide) -> Void

    var body: some View {
        List {
            ForEach(viewModel.upNextQueue) { guide in
                AudioGuideRowView(
                    guide: guide,
                    isPlaying: viewModel.currentGuide?.id == guide.id,
                    progress: viewModel.playbackProgress[guide.id],
                    showMenu: false,
                    onPlay: { viewModel.playGuide(guide) },
                    onOpenPlayer: { onOpenPlayer(guide) }
                ) {
                    EmptyView()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                viewModel.reorderQueue(from: source, to: destination)
            }

            if viewModel.upNextQueue.isEmpty {
                Text("Nothing queued — pick from Discover")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .padding(.top, 40)
            }
            
            Color.clear
                .frame(height: bottomPadding)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.editMode, .constant(.active))
    }
}

struct DiscoverListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    var bottomPadding: CGFloat = 0
    var onOpenPlayer: (AudioGuide) -> Void

    var body: some View {
        List {
            ForEach(viewModel.filteredDiscoverList) { guide in
                AudioGuideRowView(
                    guide: guide,
                    isPlaying: viewModel.currentGuide?.id == guide.id,
                    progress: nil,
                    isRecentlyQueued: viewModel.recentlyQueuedGuideId == guide.id,
                    onPlay: { viewModel.playGuide(guide) },
                    onOpenPlayer: { onOpenPlayer(guide) },
                    onCreate: { viewModel.requestCreation(for: guide) }
                ) {
                    if guide.status == .ready {
                        Button {
                            viewModel.playNextInQueue(guide)
                        } label: {
                            Label("Play Next", systemImage: "text.insert")
                        }
                        
                        Button {
                            viewModel.addToQueue(guide)
                        } label: {
                            Label("Add to End", systemImage: "text.append")
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    if guide.status == .ready {
                        Button {
                            viewModel.addToQueue(guide)
                        } label: {
                            Label("Queue", systemImage: "text.append")
                        }
                        .tint(BrandColors.logo)
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
    }
}

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
                    
                    // User-requested separator after header
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

#Preview {
    AudioGuidesPageView()
}
