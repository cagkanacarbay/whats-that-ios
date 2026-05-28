import Foundation

/// A curated discovery shown during pre-onboarding before user sign-up.
/// These are stored in the sample_discoveries table and are publicly accessible.
public struct SampleDiscovery: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let shortDescription: String?
    public let description: String?
    public let imagePath: String        // e.g., "samples/1.jpg"
    public let voiceoverPath: String?   // e.g., "samples/1.mp3"
    public let createdAt: Date

    public init(
        id: Int,
        title: String,
        shortDescription: String?,
        description: String?,
        imagePath: String,
        voiceoverPath: String?,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.shortDescription = shortDescription
        self.description = description
        self.imagePath = imagePath
        self.voiceoverPath = voiceoverPath
        self.createdAt = createdAt
    }
}

extension SampleDiscovery {
    /// Converts to DiscoverySummary for use with existing UI components.
    /// - Parameter signedImageURL: The signed URL for the image, obtained from storage.
    /// - Returns: A DiscoverySummary suitable for display in discovery cards and detail views.
    public func asDiscoverySummary(signedImageURL: String?) -> DiscoverySummary {
        let highlight = shortDescription ?? description?.prefix(200).description ?? "Explore this discovery"
        return DiscoverySummary(
            id: Int64(id),
            title: title,
            highlight: highlight,
            shortDescription: shortDescription,
            detailDescription: description,
            capturedAt: createdAt,
            imagePath: signedImageURL,
            imageStoragePath: imagePath,
            shareToken: nil,    // No sharing for samples
            location: nil       // No location for samples
        )
    }
}
