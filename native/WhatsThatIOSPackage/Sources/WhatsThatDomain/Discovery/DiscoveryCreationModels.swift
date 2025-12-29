import Foundation

public enum DiscoveryCreationFlowType: String, Equatable, Sendable {
    case camera
    case upload
}

public enum DiscoveryAnalysisError: LocalizedError, Equatable, Sendable {
    case unauthenticated
    case invalidResponse
    case unexpectedStatus(Int)
    case streamInterrupted

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "You need to sign in before creating a discovery."
        case .invalidResponse:
            return "The analysis service returned an unexpected response."
        case let .unexpectedStatus(code):
            return "The analysis service returned status code \(code)."
        case .streamInterrupted:
            return "The connection was interrupted. Your discovery may still be processing."
        }
    }
}

public enum DiscoveryFlowCancellationError: Error, Equatable, Sendable {
    case userCancelled

    public static func isCancellation(_ error: Error) -> Bool {
        if let cancellation = error as? DiscoveryFlowCancellationError, cancellation == .userCancelled {
            return true
        }

        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }

        return false
    }
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
    public var isResolvingLocation: Bool
    public var customContext: String?
    public var nearbyPlaces: [NearbyPlace]?
    public var nearbyPlacesContext: NearbyPlacesContext?

    public init(
        media: DiscoveryCapturedMedia,
        displayImageData: Data,
        creditBalance: Int? = nil,
        location: DiscoveryLocation? = nil,
        locationDescription: String? = nil,
        isLocationPermissionGranted: Bool,
        isResolvingLocation: Bool = false,
        customContext: String? = nil,
        nearbyPlaces: [NearbyPlace]? = nil,
        nearbyPlacesContext: NearbyPlacesContext? = nil
    ) {
        self.media = media
        self.displayImageData = displayImageData
        self.creditBalance = creditBalance
        self.location = location
        self.locationDescription = locationDescription
        self.isLocationPermissionGranted = isLocationPermissionGranted
        self.isResolvingLocation = isResolvingLocation
        self.customContext = customContext
        self.nearbyPlaces = nearbyPlaces
        self.nearbyPlacesContext = nearbyPlacesContext
    }
}

public struct DiscoveryAnalysisState: Equatable, Sendable {
    public var statusMessage: String?
    public var streamedText: String
    public var isStreaming: Bool
    public var isPolling: Bool
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
        isPolling: Bool = false,
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
        self.isPolling = isPolling
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

public enum DiscoveryCreationPhase: Equatable, Sendable {
    case idle
    case requestingPermissions
    case capturingInitial
    case capturingRetake
    case selectingInitial
    case selectingRetake
    case confirming
    case analyzing
    case cancelled
    case error
}

public extension DiscoveryCreationFlowState {
    var phase: DiscoveryCreationPhase {
        switch self {
        case .idle: return .idle
        case .requestingPermissions: return .requestingPermissions
        case .capturingInitial: return .capturingInitial
        case .capturingRetake: return .capturingRetake
        case .selectingInitial: return .selectingInitial
        case .selectingRetake: return .selectingRetake
        case .confirming: return .confirming
        case .analyzing: return .analyzing
        case .cancelled: return .cancelled
        case .error: return .error
        }
    }
}

public enum DiscoveryAnalysisEvent: Sendable, Equatable {
    case status(String)
    case metadata(title: String?, shortDescription: String?)
    case token(String)
    case complete(discoveryId: Int64, systemPromptVersion: String?, userPromptVersion: String?, creditBalance: Int?)
    case error(message: String, status: Int? = nil)
    case end
}
