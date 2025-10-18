import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
#if canImport(MapKit)
import MapKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DiscoveryCreationDetailView: View {
    private enum Layout {
        static let headerHeightFactor: CGFloat = 0.8
        static let imageAspectRatio: CGFloat = 1.2
        static let minimumHeaderHeight: CGFloat = 360
    }

    let discovery: DiscoverySummary
    let previewImage: DetailPlatformImage?
    let remoteImageURL: URL?
    let onClose: () -> Void
    let onShare: (() -> Void)?
    let onShowOptions: (() -> Void)?

    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Environment(\.colorScheme) private var colorScheme

    init(
        discovery: DiscoverySummary,
        previewImage: DetailPlatformImage?,
        remoteImageURL: URL?,
        voiceoverController: VoiceoverPlaybackController,
        onClose: @escaping () -> Void,
        onShare: (() -> Void)?,
        onShowOptions: (() -> Void)?
    ) {
        self.discovery = discovery
        self.previewImage = previewImage
        self.remoteImageURL = remoteImageURL
        self.onClose = onClose
        self.onShare = onShare
        self.onShowOptions = onShowOptions
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight = resolvedHeaderHeight(for: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header(height: headerHeight)
                    contentSection
                        .padding(.top, BrandSpacing.large)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.xLarge * 2 + additionalBottomPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.background)
                }
            }
            .background(palette.background.ignoresSafeArea())
            .overlay(
                topControls(padding: resolvedTopPadding(from: proxy.safeAreaInsets)),
                alignment: .topLeading
            )
        }
        .onAppear {
            voiceoverController.isDetailOverlayActive = true
            voiceoverController.ensureMetadata(for: discovery)
        }
        .onDisappear {
            voiceoverController.stopIfPlaying(discoveryId: discovery.id)
            voiceoverController.isDetailOverlayActive = false
        }
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private func resolvedHeaderHeight(for size: CGSize) -> CGFloat {
        let proposed = size.height * Layout.headerHeightFactor
        let ratio = size.width * Layout.imageAspectRatio
        let preferred = min(proposed, ratio)
        return max(preferred, Layout.minimumHeaderHeight)
    }

    private func header(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            headerImage(height: height)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0),
                    .init(color: palette.overlayMidtone, location: 0.7),
                    .init(color: palette.background, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: BrandSpacing.small) {
                Text(discovery.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(discovery.capturedAt.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)

                if let short = discovery.shortDescription?.trimmedNonEmptyOrNil ?? discovery.highlight.trimmedNonEmptyOrNil {
                    Text(short)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.large)
                }
            }
            .padding(.bottom, BrandSpacing.xLarge)
            .padding(.horizontal, BrandSpacing.large)

            HStack {
                if discovery.location != nil {
                    buttonCircle(systemName: "mappin.and.ellipse") {
                        openInMaps()
                    }
                }

                Spacer()

                if let onShare {
                    buttonCircle(systemName: "square.and.arrow.up", action: onShare)
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, 28)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func headerImage(height: CGFloat) -> some View {
        ZStack {
            if let previewImage {
                Image(platformImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                placeholderGradient
            }

            DiscoveryCachedImage(
                discoveryId: discovery.id,
                remoteURL: remoteImageURL
            ) { phase in
                switch phase {
                case .success(let platformImage):
                    Image(platformImage: platformImage)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                case .loading, .empty:
                    if previewImage == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(palette.primaryAction)
                    } else {
                        Color.clear
                    }
                case .failure:
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.large) {
            VoiceoverDetailButton(
                discovery: discovery,
                controller: voiceoverController,
                palette: palette
            )

            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                Text(discovery.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                detailDescription
            }
        }
    }

    @ViewBuilder
    private var detailDescription: some View {
        if let description = discovery.detailDescription, !description.isEmpty {
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
            Text(discovery.highlight)
                .font(.system(size: 16))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func topControls(padding: CGFloat) -> some View {
        HStack {
            Button(action: {
                voiceoverController.stopIfPlaying(discoveryId: discovery.id)
                onClose()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.overlayButtonForeground)
                    .padding(14)
                    .background(palette.overlayButtonBackground)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(palette.overlayButtonBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 8, x: 0, y: 4)

            Spacer()

            if let onShowOptions {
                Button(action: onShowOptions) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(palette.overlayButtonForeground)
                        .padding(14)
                        .background(palette.overlayButtonBackground)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(palette.overlayButtonBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.top, padding)
        .padding(.bottom, BrandSpacing.small)
    }

    private var additionalBottomPadding: CGFloat {
        switch voiceoverController.playbackState {
        case .idle, .unavailable:
            return 0
        default:
            return 132
        }
    }

    private func buttonCircle(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.overlayButtonForeground)
                .padding(16)
                .background(palette.overlayButtonBackground)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(palette.overlayButtonBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 8, x: 0, y: 4)
    }

    private func openInMaps() {
        guard let location = discovery.location else { return }
        #if canImport(MapKit)
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = discovery.title
        mapItem.openInMaps()
        #endif
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

    private var placeholderGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "#20293A"),
                Color(hex: "#141927")
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#if canImport(UIKit)
typealias DetailPlatformImage = UIImage
#elseif canImport(AppKit)
typealias DetailPlatformImage = NSImage
#endif

private extension Image {
#if canImport(UIKit)
    init(platformImage: DetailPlatformImage) {
        self.init(uiImage: platformImage)
    }
#elseif canImport(AppKit)
    init(platformImage: DetailPlatformImage) {
        self.init(nsImage: platformImage)
    }
#endif
}

private extension VoiceoverPlaybackController {
    func stopIfPlaying(discoveryId: Int64) {
        switch playbackState {
        case let .playing(id) where id == discoveryId,
             let .paused(id) where id == discoveryId:
            stop()
            isDetailOverlayActive = false
        default:
            break
        }
    }
}

private extension String {
    var trimmedNonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
