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
        let headline = "Check out this \"\(title)\" I discovered on \"What's That?\""

        var components: [String] = [headline]
        if let link = shareLinkURL(for: context.discovery)?.absoluteString {
            components.append(link)
        }

        let message = components.joined(separator: "\n\n")
        let shareImage = await resolvedShareImage(for: context)

        var items: [Any] = [
            DiscoveryShareMetadataItem(
                message: message,
                title: title,
                link: shareLinkURL(for: context.discovery),
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

        if let link = shareLinkURL(for: context.discovery) {
            items.append(link)
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
        components.path = "/\(token.uuidString.lowercased())"
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
