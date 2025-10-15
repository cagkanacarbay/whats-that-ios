import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
import MapKit

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
    @Environment(\.colorScheme) private var colorScheme

    private let headerHeightFactor: CGFloat = 0.72

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
                .opacity(isContentVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isContentVisible)

                headerTopControls(padding: proxy.safeAreaInsets.top + 12)
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
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
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
                .foregroundStyle(Color.white)
                .padding(16)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func headerOverlay(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.0),
                    colorScheme == .dark
                        ? BrandColors.Dark.background.opacity(0.92)
                        : BrandColors.Light.background.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: BrandSpacing.small) {
                Text(discovery.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                Text(discovery.capturedAt.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))

                if let shortDescription = discovery.shortDescription ?? discovery.highlight.nonEmptyOrNil {
                    Text(shortDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.85))
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
                    .background(BrandColors.Dark.primaryAction)
                    .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.large, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                Text(discovery.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textColor)

                detailDescriptionView
            }
        }
    }

    private var textColor: Color {
        colorScheme == .dark ? BrandColors.Dark.accentText : BrandColors.Light.accentText
    }

    @ViewBuilder
    private var detailDescriptionView: some View {
        if let description = discovery.detailDescription, !description.isEmpty {
            #if canImport(MarkdownUI)
            Markdown(description)
                .markdownTextStyle {
                    ForegroundColor(textColor.opacity(0.88))
                }
                .textSelection(.enabled)
            #else
            Text(description)
                .font(.system(size: 16))
                .foregroundStyle(textColor.opacity(0.88))
            #endif
        } else {
            Text(discovery.highlight)
                .font(.system(size: 16))
                .foregroundStyle(textColor.opacity(0.75))
        }
    }

    private func headerTopControls(padding: CGFloat) -> some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(14)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

            Spacer()

            if let optionsAction = onShowOptions {
                Button(action: optionsAction) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Color.white)
                        .padding(14)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.top, padding)
        .padding(.bottom, BrandSpacing.small)
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

    @State private var didFail = false

    var body: some View {
        ZStack {
            placeholder

            if let imageURL, !didFail {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        Color.clear
                            .onAppear { didFail = true }
                    case .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.white)
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

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
