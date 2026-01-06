#if canImport(UIKit) && canImport(Photos)
import Foundation
import Photos
import UIKit
import WhatsThatDomain

/// Service for saving images to the user's Photos library with proper permission handling.
@MainActor
public final class PhotoLibrarySaveService: PhotoLibrarySaveServiceProtocol {
    
    public init() {}
    
    // MARK: - Permission Status
    
    /// Returns the current authorization status for add-only access.
    public func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .limited:
            return .limited
        @unknown default:
            return .denied
        }
    }
    
    /// Returns whether permission is currently granted (authorized or limited).
    public var isAuthorized: Bool {
        let status = authorizationStatus()
        return status == .authorized || status == .limited
    }
    
    /// Returns whether permission has been explicitly denied or restricted.
    public var isDeniedOrRestricted: Bool {
        let status = authorizationStatus()
        return status == .denied || status == .restricted
    }
    
    // MARK: - Request Permission
    
    /// Requests add-only photo library permission.
    /// Returns the new authorization status after the user responds.
    public func requestPermission() async -> PhotoLibraryAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .limited:
            return .limited
        @unknown default:
            return .denied
        }
    }
    
    // MARK: - Save Image
    
    /// Saves an image to the Photos library.
    /// If permission hasn't been determined, requests it first.
    /// - Parameter imageData: JPEG or PNG image data to save
    /// - Returns: Result indicating success or failure reason
    public func save(imageData: Data) async -> PhotoLibrarySaveResult {
        // Check current permission
        var currentStatus = authorizationStatus()
        
        // Request permission if not determined
        if currentStatus == .notDetermined {
            currentStatus = await requestPermission()
        }
        
        // Handle denied/restricted
        switch currentStatus {
        case .denied:
            return .permissionDenied
        case .restricted:
            return .permissionRestricted
        case .authorized, .limited:
            break
        case .notDetermined:
            // User dismissed the dialog without choosing - treat as denied
            return .permissionDenied
        }
        
        // Save to Photos library
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let image = UIImage(data: imageData) else {
                    return
                }
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .success
        } catch {
            return .saveFailed(error)
        }
    }
    
    /// Saves a UIImage to the Photos library.
    /// - Parameter image: Image to save (must be a UIImage)
    /// - Returns: Result indicating success or failure reason
    public func save(image: Any) async -> PhotoLibrarySaveResult {
        guard let uiImage = image as? UIImage else {
            return .saveFailed(NSError(domain: "PhotoLibrarySaveService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Image must be a UIImage"
            ]))
        }
        guard let data = uiImage.jpegData(compressionQuality: 0.95) else {
            return .saveFailed(NSError(domain: "PhotoLibrarySaveService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode image as JPEG"
            ]))
        }
        return await save(imageData: data)
    }
}
#endif
