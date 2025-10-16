import Foundation

public enum DiscoveryCreationFlowType: String, Equatable, Sendable {
    case camera
    case upload
}

public struct DiscoveryCapturedMedia: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let data: Data
    public let contentType: String
    public let originalFilename: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let createdAt: Date
    public let location: DiscoveryLocation?

    public init(
        id: UUID = UUID(),
        data: Data,
        contentType: String,
        originalFilename: String? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date,
        location: DiscoveryLocation? = nil
    ) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.originalFilename = originalFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.location = location
    }
}

public struct DiscoveryConfirmationState: Equatable, Sendable {
    public var media: DiscoveryCapturedMedia
    public var displayImageData: Data
    public var creditBalance: Int?
    public var location: DiscoveryLocation?
    public var locationDescription: String?
    public var isLocationPermissionGranted: Bool
    public var customContext: String?

    public init(
        media: DiscoveryCapturedMedia,
        displayImageData: Data,
        creditBalance: Int? = nil,
        location: DiscoveryLocation? = nil,
        locationDescription: String? = nil,
        isLocationPermissionGranted: Bool,
        customContext: String? = nil
    ) {
        self.media = media
        self.displayImageData = displayImageData
        self.creditBalance = creditBalance
        self.location = location
        self.locationDescription = locationDescription
        self.isLocationPermissionGranted = isLocationPermissionGranted
        self.customContext = customContext
    }
}

public struct DiscoveryAnalysisState: Equatable, Sendable {
    public var statusMessage: String?
    public var streamedText: String
    public var isStreaming: Bool
    public var discoveryIdentifier: Int64?
    public var systemPromptVersion: String?
    public var userPromptVersion: String?
    public var metadataTitle: String?
    public var metadataShortDescription: String?
    public var displayMarkdown: String
    public var discoverySummary: DiscoverySummary?

    public init(
        statusMessage: String? = nil,
        streamedText: String = "",
        isStreaming: Bool = true,
        discoveryIdentifier: Int64? = nil,
        systemPromptVersion: String? = nil,
        userPromptVersion: String? = nil,
        metadataTitle: String? = nil,
        metadataShortDescription: String? = nil,
        displayMarkdown: String = "",
        discoverySummary: DiscoverySummary? = nil
    ) {
        self.statusMessage = statusMessage
        self.streamedText = streamedText
        self.isStreaming = isStreaming
        self.discoveryIdentifier = discoveryIdentifier
        self.systemPromptVersion = systemPromptVersion
        self.userPromptVersion = userPromptVersion
        self.metadataTitle = metadataTitle
        self.metadataShortDescription = metadataShortDescription
        self.displayMarkdown = displayMarkdown
        self.discoverySummary = discoverySummary
    }
}

public enum DiscoveryCreationFlowState: Equatable, Sendable {
    case idle
    case requestingPermissions
    case capturingInitial
    case capturingRetake
    case selectingInitial
    case selectingRetake
    case confirming(DiscoveryConfirmationState)
    case analyzing(DiscoveryAnalysisState)
    case cancelled
    case error(message: String)
}

public enum DiscoveryAnalysisEvent: Sendable, Equatable {
    case status(String)
    case token(String)
    case complete(discoveryId: Int64, systemPromptVersion: String?, userPromptVersion: String?)
    case error(message: String)
    case end
}
