import SwiftUI
import os
import WhatsThatShared

struct ListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AudioGuidesPageView: View {
    @StateObject private var viewModel = AudioGuidesViewModel()
    @Environment(\.colorScheme) var colorScheme
    private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "AudioGuidesPageView")
    
    @State private var showMiniPlayer: Bool = false
    @State private var listHeight: CGFloat = 0
    @State private var hasCollapsedHero: Bool = false
    @State private var lastCollapseLog: Bool = false
    @State private var isExpanding: Bool = false
    
    // Temporarily disable mini player for debugging the clipping issue.
    private let miniPlayerEnabled = false
    
    private let heroHeight: CGFloat = 320 // approximate height of hero + padding
    private let collapseTriggerOffset: CGFloat = 150 // trigger collapse after scrolling down
    private let collapseHysteresis: CGFloat = 24 // buffer to avoid flicker when hovering around threshold
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            BrandTheme.palette(for: colorScheme).background
                .ignoresSafeArea()
            
            GeometryReader { viewport in
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            // Hero inside scroll content to keep stacking order with tabs/list
                            HeroPlayerView(viewModel: viewModel)
                                .padding(.top, 20)
                                .padding(.bottom, 30)
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity)
                                .id("heroSection")
                            
                            Color.clear.frame(height: 0).id("contentTop")
                            
                            // Sticky Tabs Section
                            Section(header: 
                                ToggleBarHeaderView(
                                    selectedList: $viewModel.selectedList
                                )
                                .id("stickyHeader")
                            ) {
                                // List Content
                                Group {
                                    if viewModel.selectedList == .upNext {
                                        UpNextListView(viewModel: viewModel)
                                    } else {
                                        DiscoverListView(viewModel: viewModel)
                                    }
                                }
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(key: ListHeightPreferenceKey.self, value: proxy.size.height)
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .top)
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 20)
                                        .onEnded { value in
                                            handleHorizontalSwipe(translation: value.translation)
                                        }
                                )
                            }
                        }
                        // Guarantee enough scroll distance to collapse hero even with short lists, without removing content later.
                        // Use viewport height plus hero and header heights so this adapts to device size.
                        .frame(
                            minHeight: viewport.size.height
                                + heroHeight
                                + collapseHysteresis
                                + viewport.safeAreaInsets.top
                                + viewport.safeAreaInsets.bottom
                                + 52, // header/tabs height
                            alignment: .top
                        )
                        // Keep all content below the top safe area so nothing renders in the notch.
                        .padding(.top, viewport.safeAreaInsets.top)
                        .background(
                            GeometryReader { proxy in
                                let offset = -proxy.frame(in: .named("scroll")).minY
                                Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: offset as CGFloat?)
                            }
                        )
                    }
                    .scrollClipDisabled(false)
                    .clipped()
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                        guard let offset else {
                            log.debug("Scroll offset nil; ignoring update")
                            return
                        }
                        let threshold = (heroHeight * 0.5)
                        let showThreshold = threshold + collapseHysteresis
                        
                        // If we are programmatically expanding, ignore collapse triggers until we are back near the top.
                        if isExpanding {
                            if offset < threshold {
                                isExpanding = false
                                log.debug("Expansion scroll complete (offset < threshold)")
                            }
                            return
                        }
                        
                        if !hasCollapsedHero && offset >= showThreshold {
                            if miniPlayerEnabled {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showMiniPlayer = true
                                }
                            }
                            hasCollapsedHero = true
                            lastCollapseLog = true
                            log.debug("Collapse triggered by scroll offset \(offset, privacy: .public) >= showThreshold \(showThreshold, privacy: .public)")
                        } else if hasCollapsedHero && offset <= -10 {
                            log.debug("Expand triggered by pull-down offset \(offset, privacy: .public)")
                            lastCollapseLog = false
                            hasCollapsedHero = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showMiniPlayer = false
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo("heroSection", anchor: .top)
                            }
                        }
                    }
                    .onPreferenceChange(ListHeightPreferenceKey.self) { height in
                        listHeight = height
                        log.debug("List height updated: \(height, privacy: .public)")
                    }
                    .onChange(of: showMiniPlayer) { collapsed in
                        log.debug("showMiniPlayer changed to \(collapsed, privacy: .public) hasCollapsedHero=\(hasCollapsedHero, privacy: .public)")
                        // Only auto-scroll to sticky header if we aren't manually expanding/scrolling to top
                        if miniPlayerEnabled && collapsed && hasCollapsedHero && !isExpanding {
                            DispatchQueue.main.async {
                                log.debug("Scrolling to stickyHeader to pin list")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrollProxy.scrollTo("stickyHeader", anchor: .top)
                                }
                            }
                        }
                    }
                    .onChange(of: hasCollapsedHero) { collapsed in
                        guard !miniPlayerEnabled else { return }
                        if collapsed && !isExpanding {
                            DispatchQueue.main.async {
                                log.debug("Scrolling to stickyHeader (mini disabled)")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrollProxy.scrollTo("stickyHeader", anchor: .top)
                                }
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if showMiniPlayer && miniPlayerEnabled {
                            Color.clear.frame(height: 96)
                        }
                    }
                    
                    if showMiniPlayer && miniPlayerEnabled {
                        MiniPlayerView(viewModel: viewModel) {
                            log.debug("Mini player tapped to expand")
                            isExpanding = true
                            lastCollapseLog = false
                            hasCollapsedHero = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showMiniPlayer = false
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo("heroSection", anchor: .top)
                            }
                        }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
            }
        }
    }
}

private extension AudioGuidesPageView {
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
}



struct ToggleBarView: View {
    @Binding var selectedList: AudioGuideListType
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            toggleButton(title: "Up Next", type: .upNext)
            toggleButton(title: "Discover", type: .discover)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(BrandTheme.palette(for: colorScheme).border),
            alignment: .bottom
        )
    }
    
    private func toggleButton(title: String, type: AudioGuideListType) -> some View {
        Button(action: {
            withAnimation {
                selectedList = type
            }
        }) {
            VStack(spacing: 4) {
                Text(title)
                    .fontWeight(selectedList == type ? .bold : .medium)
                    .foregroundColor(selectedList == type ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textSecondary)
                
                if selectedList == type {
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
    
    @Namespace private var namespace
}

private struct ToggleBarHeaderView: View {
    @Binding var selectedList: AudioGuideListType
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ToggleBarView(selectedList: $selectedList)
            .frame(maxWidth: .infinity)
            .background(
                BrandTheme.palette(for: colorScheme).background
            )
            .zIndex(5)
    }
}

struct UpNextListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.upNextQueue) { guide in
                AudioGuideRowView(guide: guide, isPlaying: viewModel.currentGuide?.id == guide.id) {
                    viewModel.playGuide(guide)
                }
                Divider().padding(.leading, 80)
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
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.discoverList) { guide in
                AudioGuideRowView(guide: guide, isPlaying: viewModel.currentGuide?.id == guide.id) {
                    viewModel.playGuide(guide)
                }
                Divider().padding(.leading, 80)
            }
        }
    }
}

#Preview {
    AudioGuidesPageView()
}
