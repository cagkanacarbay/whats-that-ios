#if canImport(UIKit) && canImport(PhotosUI)
import Photos
@preconcurrency import PhotosUI
import UIKit
import UniformTypeIdentifiers
import WhatsThatDomain

public enum PhotoLibrarySelectionError: Error {
    case unavailable
    case cancelled
    case loadingFailed
}

@MainActor
public final class PhotoLibrarySelectionService: NSObject, DiscoverySelectionService {
    private var continuation: CheckedContinuation<DiscoveryCapturedMedia, Error>?

    public override init() {
        super.init()
    }

    public func requestPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    public func selectPhoto() async throws -> DiscoveryCapturedMedia {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .current

        resumeCancellationIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            picker.presentationController?.delegate = self
            self.continuation = continuation

            guard let presenter = CameraCaptureService.topViewController() else {
                continuation.resume(throwing: PhotoLibrarySelectionError.unavailable)
                self.continuation = nil
                return
            }

            presenter.present(picker, animated: true)
        }
    }

    private func loadAsset(
        _ result: PHPickerResult,
        in picker: PHPickerViewController,
        continuation: CheckedContinuation<DiscoveryCapturedMedia, Error>
    ) {
        guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
            continuation.resume(throwing: PhotoLibrarySelectionError.loadingFailed)
            picker.dismiss(animated: true)
            return
        }

        let itemProvider = result.itemProvider
        let assetIdentifier = result.assetIdentifier
        let suggestedName = result.itemProvider.suggestedName

        itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            DispatchQueue.main.async {
                if let error {
                    continuation.resume(throwing: error)
                    picker.dismiss(animated: true)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: PhotoLibrarySelectionError.loadingFailed)
                    picker.dismiss(animated: true)
                    return
                }

                var location: DiscoveryLocation?
                if let assetId = assetIdentifier {
                    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                    if let asset = assets.firstObject, let assetLocation = asset.location {
                        location = DiscoveryLocation(
                            latitude: assetLocation.coordinate.latitude,
                            longitude: assetLocation.coordinate.longitude,
                            country: nil,
                            locality: nil,
                            streetName: nil,
                            closestPlace: nil
                        )
                    }
                }

                if let image = UIImage(data: data) {
                    let media = DiscoveryCapturedMedia(
                        data: data,
                        contentType: "image/jpeg",
                        originalFilename: suggestedName,
                        pixelWidth: Int(image.size.width * image.scale),
                        pixelHeight: Int(image.size.height * image.scale),
                        createdAt: Date(),
                        location: location
                    )

                    continuation.resume(returning: media)
                } else {
                    continuation.resume(throwing: PhotoLibrarySelectionError.loadingFailed)
                }

                picker.dismiss(animated: true)
            }
        }
    }
}

extension PhotoLibrarySelectionService: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let continuation else {
            picker.dismiss(animated: true)
            return
        }

        guard let result = results.first else {
            resumeCancellationIfNeeded()
            picker.dismiss(animated: true)
            return
        }

        self.continuation = nil
        loadAsset(result, in: picker, continuation: continuation)
    }
}

extension PhotoLibrarySelectionService: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController is PHPickerViewController else { return }
        resumeCancellationIfNeeded()
    }
}

private extension PhotoLibrarySelectionService {
    func resumeCancellationIfNeeded() {
        guard let continuation else { return }
        continuation.resume(throwing: DiscoveryFlowCancellationError.userCancelled)
        self.continuation = nil
    }
}
#endif
