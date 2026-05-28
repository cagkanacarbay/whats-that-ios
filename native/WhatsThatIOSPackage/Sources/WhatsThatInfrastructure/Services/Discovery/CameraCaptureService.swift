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
    private weak var activePicker: UIImagePickerController?
    private var isPresentingPicker = false

    #if DEBUG
    private static func debugLog(_ message: String) {
        print("[CameraCaptureService] \(message)")
    }
    #endif

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
            #if DEBUG
            Self.debugLog("capturePhoto() unavailable: camera source not available")
            #endif
            throw CameraCaptureError.unavailable
        }

        #if DEBUG
        Self.debugLog(
            "capturePhoto() called; existingContinuation=\(continuation != nil) isPresentingPicker=\(isPresentingPicker)"
        )
        #endif

        if isPresentingPicker {
            #if DEBUG
            Self.debugLog("capturePhoto() aborted: picker already active; treating as user cancellation")
            #endif
            throw DiscoveryFlowCancellationError.userCancelled
        }

        if continuation != nil {
            #if DEBUG
            Self.debugLog("Cancelling existing continuation before starting new capture")
            #endif
            continuation?.resume(throwing: DiscoveryFlowCancellationError.userCancelled)
            continuation = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
            picker.allowsEditing = false
            picker.delegate = self

            self.continuation = continuation
            self.activePicker = picker
            #if DEBUG
            Self.debugLog("Resolving presenter via topViewController()")
            #endif
            guard let presenter = Self.topViewController() else {
                #if DEBUG
                Self.debugLog("capturePhoto() failed: no presenter (topViewController returned nil)")
                #endif
                continuation.resume(throwing: CameraCaptureError.unavailable)
                self.continuation = nil
                 self.activePicker = nil
                return
            }

            #if DEBUG
            let presenterType = String(describing: type(of: presenter))
            let hasWindow = presenter.viewIfLoaded?.window != nil
            let isBeingDismissed = presenter.isBeingDismissed
            let isMovingFromParent = presenter.isMovingFromParent
            Self.debugLog("Using presenter=\(presenterType) hasWindow=\(hasWindow) isBeingDismissed=\(isBeingDismissed) isMovingFromParent=\(isMovingFromParent)")
            #endif

            // Verify presenter is in a valid state to present.
            // If the presenter is being dismissed or has no window, presentation will fail silently
            // and leave isPresentingPicker stuck true, causing subsequent captures to abort.
            if presenter.isBeingDismissed || presenter.isMovingFromParent || presenter.viewIfLoaded?.window == nil {
                #if DEBUG
                Self.debugLog("Presenter not in valid state for presentation, aborting capture")
                #endif
                continuation.resume(throwing: DiscoveryFlowCancellationError.userCancelled)
                self.continuation = nil
                self.activePicker = nil
                return
            }

            self.isPresentingPicker = true
            presenter.present(picker, animated: true)
        }
    }

    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController

        var current = base
        var chainDescription: [String] = []

        var depth = 0
        while let controller = current, depth < 8 {
            let typeName = String(describing: type(of: controller))
            let hasWindow = controller.viewIfLoaded?.window != nil
            chainDescription.append("\(typeName)(hasWindow=\(hasWindow))")

            if let nav = controller as? UINavigationController {
                current = nav.visibleViewController
            } else if let tab = controller as? UITabBarController {
                current = tab.selectedViewController
            } else if let presented = controller.presentedViewController {
                current = presented
            } else {
                break
            }

            depth += 1
        }

        #if DEBUG
        if chainDescription.isEmpty {
            debugLog("topViewController chain: <none>")
        } else {
            debugLog("topViewController chain: \(chainDescription.joined(separator: " -> "))")
        }
        #endif

        return current
    }
}

extension CameraCaptureService: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        defer {
            let pickerToDismiss = picker
            pickerToDismiss.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                if self.activePicker === pickerToDismiss {
                    self.activePicker = nil
                }
                if self.isPresentingPicker {
                    self.isPresentingPicker = false
                    #if DEBUG
                    Self.debugLog("Picker dismissal completed after successful capture")
                    #endif
                }
            }
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
        continuation?.resume(throwing: DiscoveryFlowCancellationError.userCancelled)
        continuation = nil
        let pickerToDismiss = picker
        pickerToDismiss.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if self.activePicker === pickerToDismiss {
                self.activePicker = nil
            }
            if self.isPresentingPicker {
                self.isPresentingPicker = false
                #if DEBUG
                Self.debugLog("Picker dismissal completed after cancellation")
                #endif
            }
        }
    }
}
