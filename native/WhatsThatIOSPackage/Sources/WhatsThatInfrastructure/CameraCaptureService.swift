#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit
import WhatsThatDomain

public enum CameraCaptureError: Error {
    case unavailable
    case cancelled
    case encodingFailed
}

@MainActor
public final class CameraCaptureService: NSObject, DiscoveryCaptureService {
    private var continuation: CheckedContinuation<DiscoveryCapturedMedia, Error>?

    public override init() {
        super.init()
    }

    public func requestPermission(for type: DiscoveryCreationFlowType) async -> Bool {
        guard type == .camera else { return true }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    public func capturePhoto() async throws -> DiscoveryCapturedMedia {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw CameraCaptureError.unavailable
        }

        if continuation != nil {
            continuation?.resume(throwing: CameraCaptureError.cancelled)
            continuation = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.allowsEditing = false
            picker.delegate = self

            self.continuation = continuation
            guard let presenter = Self.topViewController() else {
                continuation.resume(throwing: CameraCaptureError.unavailable)
                self.continuation = nil
                return
            }

            presenter.present(picker, animated: true)
        }
    }

    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }

        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }

        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }

        return base
    }
}

extension CameraCaptureService: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        defer {
            picker.dismiss(animated: true)
        }

        guard
            let image = info[.originalImage] as? UIImage,
            let data = image.jpegData(compressionQuality: 0.95)
        else {
            continuation?.resume(throwing: CameraCaptureError.encodingFailed)
            continuation = nil
            return
        }

        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)

        let media = DiscoveryCapturedMedia(
            data: data,
            contentType: "image/jpeg",
            originalFilename: nil,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            createdAt: Date(),
            location: nil
        )

        continuation?.resume(returning: media)
        continuation = nil
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        continuation?.resume(throwing: CameraCaptureError.cancelled)
        continuation = nil
        picker.dismiss(animated: true)
    }
}
#endif
