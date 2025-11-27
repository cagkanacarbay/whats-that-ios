import SwiftUI
import WhatsThatShared

struct HeroVisibilityKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

struct AudioGuidesPageView: View {
    @StateObject private var viewModel = AudioGuidesViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showMiniPlayer: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            BrandTheme.palette(for: colorScheme).background
                .ignoresSafeArea()
            
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Hero Section (Scrolls away)
                        HeroPlayerView(viewModel: viewModel)
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                            .id("heroSection")
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: HeroVisibilityKey.self,
                                            value: proxy.frame(in: .global).maxY > 100
                                        )
                                }
                            )
                        
                        // Sticky Tabs Section
                        Section(header: 
                            ToggleBarView(selectedList: $viewModel.selectedList)
                                .background(BrandTheme.palette(for: colorScheme).background)
                        ) {
                            // List Content
                            Group {
                                if viewModel.selectedList == .upNext {
                                    UpNextListView(viewModel: viewModel)
                                } else {
                                    DiscoverListView(viewModel: viewModel)
                                }
                            }
                            .frame(minHeight: 400) // Ensure scrollable area
                            .padding(.bottom, 100) // Space for mini player
                            .gesture(
                                DragGesture()
                                    .onEnded { value in
                                        if value.translation.width < -50 {
                                            withAnimation { viewModel.selectedList = .discover }
                                        } else if value.translation.width > 50 {
                                            withAnimation { viewModel.selectedList = .upNext }
                                        }
                                    }
                            )
                        }
                    }
                }
                .onPreferenceChange(HeroVisibilityKey.self) { isVisible in
                    withAnimation {
                        showMiniPlayer = !isVisible
                    }
                }
                .overlay(alignment: .bottom) {
                    if showMiniPlayer {
                        MiniPlayerView(viewModel: viewModel)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onTapGesture {
                                withAnimation {
                                    scrollProxy.scrollTo("heroSection", anchor: .top)
                                }
                            }
                    }
                }
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

struct UpNextListView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Sneak Peek / Next Item Logic
            // The design says "Sneak Peek... Immediately beneath hero".
            // But if we are in "Up Next" mode, the whole list is here.
            
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

