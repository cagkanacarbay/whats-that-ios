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
                    .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace)
                    .padding(.horizontal, 8)
                    .padding(.bottom, bottomInset)
            }
        }
    }

    var listOverlay: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom

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

                    Spacer()
                }
                .padding(.top, topInset + 12)
                .padding(.horizontal, 0)

                toggleBar(enterListOnTap: false, showSelection: true)
                    .matchedGeometryEffect(id: "toggleBar", in: toggleNamespace)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: true) {
                    listContent
                        .padding(.bottom, bottomInset + miniPlayerHeight + 16)
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
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        overlayDragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        handleOverlayDragEnd(translation: value.translation)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        handleHorizontalSwipe(translation: value.translation)
                    }
            )
        }
    }

    var listContent: some View {
        Group {
            if viewModel.selectedList == .upNext {
                UpNextListView(viewModel: viewModel) { guide in
                    handleOpenPlayer(for: guide)
                }
            } else {
                DiscoverListView(viewModel: viewModel) { guide in
                    handleOpenPlayer(for: guide)
                }
            }
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

    func handleHorizontalSwipe(translation: CGSize) {
        let horizontal = translation.width
        let vertical = translation.height

        // Only treat as a tab swipe if the gesture is predominantly horizontal (at least 1.5x the vertical movement) and clears the threshold.
        guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 50 else { return }

        withAnimation {
            if horizontal < 0 {
                viewModel.selectedList = .discover
            } else {
                viewModel.selectedList = .upNext
            }
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
    var onOpenPlayer: (AudioGuide) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.upNextQueue) { guide in
                AudioGuideRowView(
                    guide: guide,
                    isPlaying: viewModel.currentGuide?.id == guide.id,
                    onPlay: { viewModel.playGuide(guide) },
                    onOpenPlayer: { onOpenPlayer(guide) }
                )
                Divider().padding(.horizontal, 16)
            }

            if viewModel.upNextQueue.isEmpty {
                Text("Nothing queued — pick from Discover")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            }
        }
    }
}

struct DiscoverListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    var onOpenPlayer: (AudioGuide) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.discoverList) { guide in
                AudioGuideRowView(
                    guide: guide,
                    isPlaying: viewModel.currentGuide?.id == guide.id,
                    onPlay: { viewModel.playGuide(guide) },
                    onOpenPlayer: { onOpenPlayer(guide) }
                )
                Divider().padding(.horizontal, 16)
            }
        }
    }
}

#Preview {
    AudioGuidesPageView()
}
