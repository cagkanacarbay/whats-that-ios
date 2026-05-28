import XCTest
@testable import WhatsThatPresentation
import WhatsThatDomain

@MainActor
final class PhotoCaptureCoordinatorTests: XCTestCase {

    private let sampleMedia = DiscoveryCapturedMedia(
        data: Data(repeating: 0xAA, count: 16),
        contentType: "image/jpeg",
        originalFilename: "test.jpg",
        pixelWidth: 1080,
        pixelHeight: 1920,
        createdAt: Date(),
        location: nil
    )

    // MARK: - capture()

    func testCameraCaptureSucceeds() async {
        let captureService = ConfigurableCaptureService(grantPermission: true, media: sampleMedia)
        let coordinator = PhotoCaptureCoordinator(
            captureService: captureService,
            selectionService: ConfigurableSelectionService(grantPermission: true, media: sampleMedia)
        )

        let result = await coordinator.capture(type: .camera)

        if case .captured(let media) = result {
            XCTAssertEqual(media.data, sampleMedia.data)
        } else {
            XCTFail("Expected .captured, got \(result)")
        }
    }

    func testCameraPermissionDenied() async {
        let captureService = ConfigurableCaptureService(grantPermission: false, media: sampleMedia)
        let coordinator = PhotoCaptureCoordinator(
            captureService: captureService,
            selectionService: ConfigurableSelectionService(grantPermission: true, media: sampleMedia)
        )

        let result = await coordinator.capture(type: .camera)

        if case .permissionDenied(let type) = result {
            XCTAssertEqual(type, .camera)
        } else {
            XCTFail("Expected .permissionDenied(.camera), got \(result)")
        }
    }

    func testGalleryPermissionDenied() async {
        let selectionService = ConfigurableSelectionService(grantPermission: false, media: sampleMedia)
        let coordinator = PhotoCaptureCoordinator(
            captureService: ConfigurableCaptureService(grantPermission: true, media: sampleMedia),
            selectionService: selectionService
        )

        let result = await coordinator.capture(type: .upload)

        if case .permissionDenied(let type) = result {
            XCTAssertEqual(type, .upload)
        } else {
            XCTFail("Expected .permissionDenied(.upload), got \(result)")
        }
    }

    func testPhotoPickerCancelled() async {
        let selectionService = ConfigurableSelectionService(grantPermission: true, media: nil, shouldCancel: true)
        let coordinator = PhotoCaptureCoordinator(
            captureService: ConfigurableCaptureService(grantPermission: true, media: sampleMedia),
            selectionService: selectionService
        )

        let result = await coordinator.capture(type: .upload)

        if case .cancelled = result {
            // Expected
        } else {
            XCTFail("Expected .cancelled, got \(result)")
        }
    }

    func testCameraCaptureFails() async {
        let captureService = ConfigurableCaptureService(grantPermission: true, media: nil, shouldFail: true)
        let coordinator = PhotoCaptureCoordinator(
            captureService: captureService,
            selectionService: ConfigurableSelectionService(grantPermission: true, media: sampleMedia)
        )

        let result = await coordinator.capture(type: .camera)

        if case .failed(let type) = result {
            XCTAssertEqual(type, .camera)
        } else {
            XCTFail("Expected .failed(.camera), got \(result)")
        }
    }

    // MARK: - captureForDiscoverMore()

    func testDiscoverMoreCaptureSucceeds() async {
        let coordinator = PhotoCaptureCoordinator(
            captureService: ConfigurableCaptureService(grantPermission: true, media: sampleMedia),
            selectionService: ConfigurableSelectionService(grantPermission: true, media: sampleMedia)
        )

        let result = await coordinator.captureForDiscoverMore(type: .camera)

        XCTAssertNotNil(result)
        if case .captured(let media) = result {
            XCTAssertEqual(media.data, sampleMedia.data)
        } else {
            XCTFail("Expected .captured, got \(String(describing: result))")
        }
    }

    func testDiscoverMorePickerCancelled() async {
        let coordinator = PhotoCaptureCoordinator(
            captureService: ConfigurableCaptureService(grantPermission: true, media: sampleMedia),
            selectionService: ConfigurableSelectionService(grantPermission: true, media: nil, shouldCancel: true)
        )

        let result = await coordinator.captureForDiscoverMore(type: .upload)

        if case .cancelled = result {
            // Expected
        } else {
            XCTFail("Expected .cancelled, got \(String(describing: result))")
        }
    }
}

// MARK: - Test Doubles

private final class ConfigurableCaptureService: DiscoveryCaptureService {
    private let grantPermission: Bool
    private let media: DiscoveryCapturedMedia?
    private let shouldFail: Bool

    init(grantPermission: Bool, media: DiscoveryCapturedMedia?, shouldFail: Bool = false) {
        self.grantPermission = grantPermission
        self.media = media
        self.shouldFail = shouldFail
    }

    func requestPermission(for type: DiscoveryCreationFlowType) async -> Bool {
        grantPermission
    }

    func capturePhoto() async throws -> DiscoveryCapturedMedia {
        if shouldFail {
            throw NSError(domain: "TestCapture", code: 1)
        }
        guard let media else {
            throw DiscoveryFlowCancellationError.userCancelled
        }
        return media
    }
}

private final class ConfigurableSelectionService: DiscoverySelectionService {
    private let grantPermission: Bool
    private let media: DiscoveryCapturedMedia?
    private let shouldCancel: Bool

    init(grantPermission: Bool, media: DiscoveryCapturedMedia?, shouldCancel: Bool = false) {
        self.grantPermission = grantPermission
        self.media = media
        self.shouldCancel = shouldCancel
    }

    func requestPermission() async -> Bool {
        grantPermission
    }

    func selectPhoto() async throws -> DiscoveryCapturedMedia {
        if shouldCancel {
            throw DiscoveryFlowCancellationError.userCancelled
        }
        guard let media else {
            throw NSError(domain: "TestSelection", code: 1)
        }
        return media
    }
}
