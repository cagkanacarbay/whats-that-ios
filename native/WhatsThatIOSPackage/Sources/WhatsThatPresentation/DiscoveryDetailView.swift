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

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: systemColorScheme)
    }

    private var overlayGradientStops: [Gradient.Stop] {
        [
            .init(color: Color.clear, location: 0.0),
            .init(color: palette.overlayMidtone, location: 0.7),
            .init(color: palette.background, location: 1.0)
        ]
    }

    private var overlayTitleColor: Color {
        palette.textPrimary
    }

    private var overlaySupportingColor: Color {
        palette.textSecondary
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
                        headerView(height: proxy.size.height * headerHeightFactor)
                        bodyContent
                            .padding(.top, BrandSpacing.large)
                            .padding(.horizontal, BrandSpacing.large)
                            .padding(.bottom, BrandSpacing.xLarge * 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
    private func headerView(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            DiscoveryImagePlaceholderView(
                imageURL: imageURL,
                height: height,
                cornerRadius: isExpanded ? 0 : BrandCornerRadius.large,
                namespace: namespace,
                discoveryId: discovery.id
            )

            headerOverlay(height: height)
                .frame(height: height)
                .allowsHitTesting(false)

            if let shareAction = onShare {
                bottomTrailingButton(systemName: "square.and.arrow.up", action: shareAction)
            }

            if let location = discovery.location {
                bottomLeadingButton(systemName: "mappin.and.ellipse") {
                    openInMaps(location: location)
                }
            }
        }
        .frame(height: height)
        .clipped()
    }

    private func bottomLeadingButton(systemName: String, action: @escaping () -> Void) -> some View {
        buttonCircle(systemName: systemName, alignment: .leading, action: action)
    }

    private func bottomTrailingButton(systemName: String, action: @escaping () -> Void) -> some View {
        buttonCircle(systemName: systemName, alignment: .trailing, action: action)
    }

    private func buttonCircle(systemName: String, alignment: HorizontalAlignment, action: @escaping () -> Void) -> some View {
        HStack {
            if alignment == .leading {
                button(systemName: systemName, action: action)
                Spacer()
            } else {
                Spacer()
                button(systemName: systemName, action: action)
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, 28)
    }

    private func button(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(overlayButtonForeground)
                .padding(16)
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

    private func headerOverlay(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(stops: overlayGradientStops),
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: BrandSpacing.small) {
                Text(discovery.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(overlayTitleColor)
                    .multilineTextAlignment(.center)

                Text(discovery.capturedAt.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(overlaySupportingColor)

                if let shortDescription = discovery.shortDescription ?? discovery.highlight.nonEmptyOrNil {
                    Text(shortDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(overlaySupportingColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.large)
                }
            }
            .padding(.bottom, BrandSpacing.xLarge)
            .padding(.horizontal, BrandSpacing.large)
        }
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

private struct DiscoveryImagePlaceholderView: View {
    let imageURL: URL?
    let height: CGFloat
    let cornerRadius: CGFloat
    let namespace: Namespace.ID
    let discoveryId: Int64

    @StateObject private var loader: DiscoveryDetailImageLoader
    @Environment(\.colorScheme) private var systemColorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: systemColorScheme)
    }

    init(
        imageURL: URL?,
        height: CGFloat,
        cornerRadius: CGFloat,
        namespace: Namespace.ID,
        discoveryId: Int64
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.namespace = namespace
        self.discoveryId = discoveryId
        _loader = StateObject(
            wrappedValue: DiscoveryDetailImageLoader(
                discoveryId: discoveryId,
                remoteURL: imageURL
            )
        )
    }

    var body: some View {
        ZStack {
            placeholder

            if let platformImage = loader.image {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if loader.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(palette.primaryAction)
            } else if loader.didFail, let fallbackURL = imageURL {
                AsyncImage(url: fallbackURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        Color.clear
                    case .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(palette.primaryAction)
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .matchedGeometryEffect(id: geometryId, in: namespace, properties: .frame, anchor: .center, isSource: true)
        .onAppear {
            loader.updateRemoteURL(imageURL)
            loader.loadIfNeeded()
        }
        .onChange(of: imageURL) { newValue in
            loader.updateRemoteURL(newValue)
            loader.loadIfNeeded()
        }
    }

    private var geometryId: String {
        "discovery-image-\(discoveryId)"
    }

    private var placeholder: some View {
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
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif

@MainActor
private final class DiscoveryDetailImageLoader: ObservableObject {
    @Published private(set) var image: PlatformImage?
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false

    private let discoveryId: Int64
    private let cache: DiscoveryAssetCache
    private let session: URLSession
    private var remoteURL: URL?

    init(
        discoveryId: Int64,
        remoteURL: URL?,
        cache: DiscoveryAssetCache = .shared,
        session: URLSession = .shared
    ) {
        self.discoveryId = discoveryId
        self.remoteURL = remoteURL
        self.cache = cache
        self.session = session
    }

    func updateRemoteURL(_ url: URL?) {
        guard remoteURL != url else { return }
        remoteURL = url
        image = nil
        didFail = false
    }

    func loadIfNeeded() {
        guard image == nil, !isLoading else { return }

        isLoading = true

        Task {
            await loadImage()
        }
    }

    private func loadImage() async {
        defer { isLoading = false }

        if let cached = await loadCachedImage() {
            image = cached
            return
        }

        guard let remoteURL else {
            didFail = true
            return
        }

        _ = await cache.ensureImageCached(
            for: discoveryId,
            signedURL: remoteURL,
            session: session
        )

        if let cached = await loadCachedImage() {
            image = cached
        } else {
            didFail = true
        }
    }

    private func loadCachedImage() async -> PlatformImage? {
        guard let fileURL = await cache.cachedImageURL(for: discoveryId) else {
            return nil
        }

        do {
            let data = try await readData(from: fileURL)
            return PlatformImage(data: data)
        } catch {
            return nil
        }
    }

    private func readData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }
}

private extension Image {
#if canImport(UIKit)
    init(platformImage: PlatformImage) {
        self = Image(uiImage: platformImage)
    }
#elseif canImport(AppKit)
    init(platformImage: PlatformImage) {
        self = Image(nsImage: platformImage)
    }
#endif
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
