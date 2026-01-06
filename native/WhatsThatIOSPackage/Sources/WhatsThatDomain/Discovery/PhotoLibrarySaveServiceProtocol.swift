import Foundation

/// Authorization status for photo library access.
public enum PhotoLibraryAuthorizationStatus: Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case limited
}

/// Result of a photo save operation.
public enum PhotoLibrarySaveResult: Sendable {
    case success
    case permissionDenied
    case permissionRestricted
    case saveFailed(Error)
}

/// Protocol for saving images to the user's Photos library.
@MainActor
public protocol PhotoLibrarySaveServiceProtocol: AnyObject {
    /// Returns the current authorization status for add-only access.
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus
    
    /// Returns whether permission is currently granted.
    var isAuthorized: Bool { get }
    
    /// Returns whether permission has been explicitly denied or restricted.
    var isDeniedOrRestricted: Bool { get }
    
    /// Requests add-only photo library permission.
    func requestPermission() async -> PhotoLibraryAuthorizationStatus
    
    /// Saves image data to the Photos library.
    func save(imageData: Data) async -> PhotoLibrarySaveResult
    
    /// Saves a UIImage to the Photos library.
    func save(image: Any) async -> PhotoLibrarySaveResult
}
