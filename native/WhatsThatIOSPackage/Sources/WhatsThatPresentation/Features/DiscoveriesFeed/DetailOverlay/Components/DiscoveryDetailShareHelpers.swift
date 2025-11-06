import SwiftUI
import UIKit
import LinkPresentation
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryDetailShareContext {
    let discovery: DiscoverySummary
    let placeholderImage: UIImage?
    let imageURL: URL?
}

struct DiscoveryDetailSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

protocol DiscoveryDetailShareHandling {
    func makeSharePayload(for context: DiscoveryDetailShareContext) async -> DiscoveryDetailSharePayload?
    func openLocationIfAvailable(from discovery: DiscoverySummary)
}

struct DiscoveryDetailShareHandler: DiscoveryDetailShareHandling {
    func makeSharePayload(for context: DiscoveryDetailShareContext) async -> DiscoveryDetailSharePayload? {
        let title = normalized(context.discovery.title) ?? "Discovery"
        let headline = "I discovered \"\(title)\" with \"What's That?\""
        let description = shareDescription(for: context.discovery)
        let linkURL = shareLinkURL(for: context.discovery)

        var components: [String] = [headline]
        if let description {
            components.append(description)
        }
        if let link = linkURL?.absoluteString {
            components.append(link)
        }

        let message = components.joined(separator: "\n\n")
        let baseShareImage = await resolvedShareImage(for: context)
        let shareImage = baseShareImage.flatMap(applyBrandMarkIfAvailable) ?? baseShareImage

        var items: [Any] = [
            DiscoveryShareMetadataItem(
                message: message,
                title: title,
                link: linkURL,
                image: shareImage
            )
        ]

        if let shareImage {
            items.append(shareImage)
        } else if let imageURL = context.imageURL {
            items.append(imageURL)
        } else if let path = context.discovery.imagePath,
                   let remoteURL = URL(string: path) {
            items.append(remoteURL)
        }

        return DiscoveryDetailSharePayload(items: items)
    }

    func openLocationIfAvailable(from discovery: DiscoverySummary) {
        guard let location = discovery.location else { return }

        var components = URLComponents(string: "http://maps.apple.com/")!
        var queryItems = [
            URLQueryItem(
                name: "ll",
                value: "\(location.latitude),\(location.longitude)"
            )
        ]

        if let label = locationQueryLabel(for: location, discovery: discovery) {
            queryItems.append(URLQueryItem(name: "q", value: label))
        }

        components.queryItems = queryItems

        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    private func shareLinkURL(for discovery: DiscoverySummary) -> URL? {
        guard let token = discovery.shareToken else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "whats-that.app"
        components.path = "/share/\(token.uuidString.lowercased())"
        return components.url
    }

    private func resolvedShareImage(for context: DiscoveryDetailShareContext) async -> UIImage? {
        if let placeholder = context.placeholderImage {
            return placeholder
        }
        if let cached = DiscoveryDetailImageCache.shared.image(for: context.discovery.id) {
            return cached
        }
        if let imageURL = context.imageURL,
           let downloaded = await downloadImage(from: imageURL) {
            DiscoveryDetailImageCache.shared.store(downloaded, for: context.discovery.id)
            return downloaded
        }
        if let path = context.discovery.imagePath,
           let remoteURL = URL(string: path),
           let downloaded = await downloadImage(from: remoteURL) {
            DiscoveryDetailImageCache.shared.store(downloaded, for: context.discovery.id)
            return downloaded
        }
        return nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shareDescription(for discovery: DiscoverySummary) -> String? {
        if let short = normalized(discovery.shortDescription) {
            return short
        }
        return normalized(discovery.highlight)
    }

    private func applyBrandMarkIfAvailable(to image: UIImage) -> UIImage? {
        guard let logo = brandLogoImage() else { return nil }
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = image.scale
        // The final composited share image is fully opaque (base photo + brand mark),
        // so render without an alpha channel to avoid ImageIO warnings and reduce size.
        rendererFormat.opaque = true
        rendererFormat.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)
        let maxLogoWidth = image.size.width * 0.28
        let maxLogoHeight = image.size.height * 0.20
        let widthScale = maxLogoWidth / max(logo.size.width, 1)
        let heightScale = maxLogoHeight / max(logo.size.height, 1)
        let scaleFactor = min(min(widthScale, heightScale), 1) * 0.75
        let targetSize = CGSize(
            width: logo.size.width * scaleFactor,
            height: logo.size.height * scaleFactor
        )
        guard targetSize.width > 0, targetSize.height > 0 else { return image }

        let edgeInset = max(image.size.width, image.size.height) * 0.01

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let origin = CGPoint(
                x: edgeInset,
                y: image.size.height - targetSize.height - edgeInset
            )
            logo.draw(
                in: CGRect(origin: origin, size: targetSize),
                blendMode: .normal,
                alpha: 0.9
            )
        }
    }

    private func brandLogoImage() -> UIImage? {
        if let cached = Self.cachedBrandLogo { return cached }
        let logo = UIImage(named: "BrandLogo")
            ?? UIImage(named: "BrandLogo", in: Bundle.main, compatibleWith: nil)
        Self.cachedBrandLogo = logo
        return logo
    }

    private static var cachedBrandLogo: UIImage?

    private func locationQueryLabel(for location: DiscoveryLocation, discovery: DiscoverySummary) -> String? {
        normalized(
            location.closestPlace
                ?? location.streetName
                ?? location.locality
                ?? location.country
                ?? discovery.title
        )
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

final class DiscoveryShareMetadataItem: NSObject, UIActivityItemSource {
    private let message: String
    private let metadata: LPLinkMetadata
    private let subject: String

    init(
        message: String,
        title: String,
        link: URL?,
        image: UIImage?
    ) {
        self.message = message
        self.subject = title
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = link
        metadata.url = link
        if let image {
            let provider = NSItemProvider(object: image)
            metadata.imageProvider = provider
            metadata.iconProvider = provider
        }
        self.metadata = metadata
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }

    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}

struct DiscoveryShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.largestUndimmedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        if let popover = controller.popoverPresentationController,
           let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
