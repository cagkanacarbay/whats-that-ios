import Foundation
import WhatsThatDomain

/// Handles photo capture and selection, including permission requests.
/// Encapsulates the camera/photo picker interaction so the ViewModel
/// only deals with the result (captured media, cancellation, or error).
@MainActor
final class PhotoCaptureCoordinator {
    enum CaptureResult {
        case captured(DiscoveryCapturedMedia)
        case cancelled
        case permissionDenied(DiscoveryCreationFlowType)
        case failed(DiscoveryCreationFlowType)
    }

    private let captureService: DiscoveryCaptureService
    private let selectionService: DiscoverySelectionService

    /// Guards against double-invocation of captureForDiscoverMore while a picker is open.
    private var isDiscoveringMore = false

    init(captureService: DiscoveryCaptureService, selectionService: DiscoverySelectionService) {
        self.captureService = captureService
        self.selectionService = selectionService
    }

    /// Main capture flow — requests permission then invokes camera/picker.
    /// The caller is responsible for setting intermediate flowState values
    /// (e.g. `.capturingInitial`) before calling this.
    func capture(type: DiscoveryCreationFlowType) async -> CaptureResult {
        switch type {
        case .camera:
            let granted = await captureService.requestPermission(for: .camera)
            guard granted else {
                return .permissionDenied(.camera)
            }
            do {
                let media = try await captureService.capturePhoto()
                await FreeCreditsAlertTracker.shared.incrementCameraUseCount()
                return .captured(media)
            } catch {
                if DiscoveryFlowCancellationError.isCancellation(error) {
                    return .cancelled
                }
                return .failed(.camera)
            }
        case .upload:
            let granted = await selectionService.requestPermission()
            guard granted else {
                return .permissionDenied(.upload)
            }
            do {
                let media = try await selectionService.selectPhoto()
                return .captured(media)
            } catch {
                if DiscoveryFlowCancellationError.isCancellation(error) {
                    return .cancelled
                }
                return .failed(.upload)
            }
        }
    }

    /// "Discover More" capture — guards against double invocation.
    /// Returns nil if already in progress (guard tripped).
    func captureForDiscoverMore(type: DiscoveryCreationFlowType) async -> CaptureResult? {
        guard !isDiscoveringMore else { return nil }
        isDiscoveringMore = true
        defer { isDiscoveringMore = false }

        switch type {
        case .camera:
            let granted = await captureService.requestPermission(for: .camera)
            guard granted else {
                return .permissionDenied(.camera)
            }
            do {
                let media = try await captureService.capturePhoto()
                await FreeCreditsAlertTracker.shared.incrementCameraUseCount()
                return .captured(media)
            } catch {
                if DiscoveryFlowCancellationError.isCancellation(error) {
                    return .cancelled
                }
                return .failed(.camera)
            }
        case .upload:
            let granted = await selectionService.requestPermission()
            guard granted else {
                return .permissionDenied(.upload)
            }
            do {
                let media = try await selectionService.selectPhoto()
                return .captured(media)
            } catch {
                if DiscoveryFlowCancellationError.isCancellation(error) {
                    return .cancelled
                }
                return .failed(.upload)
            }
        }
    }
}
