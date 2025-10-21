import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
import MapKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct DiscoveryDetailView: View {
    let discovery: DiscoverySummary
    let imageURL: URL?
    let namespace: Namespace.ID
    let isExpanded: Bool
    let onClose: () -> Void
    let onShare: (() -> Void)?
    let onShowOptions: (() -> Void)?
    let onPlayAudio: (() -> Void)?

    @State private var isContentVisible = false
    @Environment(\.colorScheme) private var systemColorScheme

    private let headerHeightFactor: CGFloat = 0.8
    private let imageAspectRatio: CGFloat = 1.2

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: systemColorScheme)
    }

    private var overlayButtonBackground: Color {
        palette.overlayButtonBackground
    }

    private var overlayButtonForeground: Color {
        palette.overlayButtonForeground
    }

    private var overlayButtonBorder: Color {
        palette.overlayButtonBorder
    }

    private var overlayButtonShadowOpacity: Double {
        palette.overlayButtonShadowOpacity
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let proposedHeight = proxy.size.height * headerHeightFactor
                        let ratioHeight = proxy.size.width * imageAspectRatio
                        let headerHeight = min(proposedHeight, ratioHeight)

                        // Reserve space for a full-bleed header that renders in an overlay
                        // ignoring the top safe area so the status bar sits on top of it.
                        Color.clear
                            .frame(height: headerHeight)

                        bodyContent
                            .padding(.top, BrandSpacing.large)
                            .padding(.horizontal, BrandSpacing.large)
                            .padding(.bottom, BrandSpacing.xLarge * 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // Render the image header outside the scrollable content so it can
                // extend behind the status bar reliably.
                .overlay(alignment: .top) {
                    let proposedHeight = proxy.size.height * headerHeightFactor
                    let ratioHeight = proxy.size.width * imageAspectRatio
                    let headerHeight = min(proposedHeight, ratioHeight)
                    headerView(width: proxy.size.width, height: headerHeight)
                        .ignoresSafeArea(edges: .top)
                }
                .id(discovery.id)
                .opacity(isContentVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isContentVisible)

                headerTopControls(padding: resolvedTopPadding(from: proxy.safeAreaInsets))
                    .opacity(isContentVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: isContentVisible)
            }
            .onChange(of: isExpanded) { expanded in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isContentVisible = expanded
                }
            }
            .onAppear {
                if isExpanded {
                    isContentVisible = true
                }
            }
        }
    }

    private var backgroundColor: Color {
        palette.background
    }

    @ViewBuilder
    private func headerView(width: CGFloat, height: CGFloat) -> some View {
        DiscoveryHeroHeaderView(
            discovery: discovery,
            imageURL: imageURL,
            placeholderImage: nil,
            preferPlaceholderImage: false,
            height: height,
            pullDownOffset: 0,
            cornerRadius: isExpanded ? 0 : BrandCornerRadius.large,
            width: width,
            namespace: namespace,
            isGeometrySource: true,
            discoveryId: discovery.id,
            palette: palette,
            onShare: onShare,
            onLocation: discovery.location.map { location in
                { openInMaps(location: location) }
            }
        )
    }

    @ViewBuilder
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.large) {
            if let playAudio = onPlayAudio {
                Button(action: playAudio) {
                    HStack {
                        Spacer()
                        Text("Play Audio Narration")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Spacer()
                    }
                    .padding()
                    .background(palette.primaryAction)
                    .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.large, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                Text(discovery.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textColor)

                detailDescriptionView(isReady: isContentVisible)
            }
        }
    }

    private var textColor: Color {
        palette.textPrimary
    }

    @ViewBuilder
    private func detailDescriptionView(isReady: Bool) -> some View {
        if let description = discovery.detailDescription, !description.isEmpty {
            if isReady {
                #if canImport(MarkdownUI)
                Markdown(description)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
                    .textSelection(.enabled)
                #else
                Text(description)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.textSecondary)
                #endif
            } else {
                EmptyView()
            }
        } else {
            Text(discovery.highlight)
                .font(.system(size: 16))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func headerTopControls(padding: CGFloat) -> some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(overlayButtonForeground)
                    .padding(14)
                    .background(overlayButtonBackground)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(overlayButtonBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(overlayButtonShadowOpacity), radius: 8, x: 0, y: 4)

            Spacer()

            if let optionsAction = onShowOptions {
                Button(action: optionsAction) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(overlayButtonForeground)
                        .padding(14)
                        .background(overlayButtonBackground)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(overlayButtonBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .shadow(color: Color.black.opacity(overlayButtonShadowOpacity), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.top, padding)
        .padding(.bottom, BrandSpacing.small)
        .zIndex(2)
    }

    private func resolvedTopPadding(from insets: EdgeInsets) -> CGFloat {
        let baseInset = insets.top
#if canImport(UIKit)
        if baseInset <= 0 {
            let globalInset = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .safeAreaInsets.top ?? 0
            return globalInset + 12
        }
#endif
        return baseInset + 12
    }

    private func openInMaps(location: DiscoveryLocation) {
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = discovery.title
        mapItem.openInMaps()
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
