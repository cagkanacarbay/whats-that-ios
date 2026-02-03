import Foundation
import XCTest
@testable import WhatsThatDomain
@testable import WhatsThatPresentation

@MainActor
final class DiscoveryDetailTransitionCoordinatorTests: XCTestCase {
    func testPresentReplacesActiveDiscoveryWhenDifferent() {
        let repository = StubVoiceoverRepository()
        let voiceoverController = VoiceoverPlaybackController(repository: repository)
        let coordinator = DiscoveryDetailTransitionCoordinator(voiceoverController: voiceoverController)

        let discoveryA = DiscoverySummary(
            id: 1,
            title: "First",
            highlight: "First highlight",
            capturedAt: Date()
        )
        let discoveryB = DiscoverySummary(
            id: 2,
            title: "Second",
            highlight: "Second highlight",
            capturedAt: Date()
        )

        let frame = CGRect(x: 10, y: 20, width: 100, height: 150)

        coordinator.present(
            discovery: discoveryA,
            cardFrame: frame,
            imageURL: nil,
            animated: false
        )

        let firstSessionId = coordinator.snapshot.context?.sessionId
        XCTAssertEqual(coordinator.snapshot.context?.discovery.id, discoveryA.id)
        XCTAssertTrue(coordinator.snapshot.phase.isActive)

        coordinator.present(
            discovery: discoveryB,
            cardFrame: frame,
            imageURL: nil,
            animated: false
        )

        let secondSessionId = coordinator.snapshot.context?.sessionId
        XCTAssertEqual(coordinator.snapshot.context?.discovery.id, discoveryB.id)
        XCTAssertNotEqual(firstSessionId, secondSessionId)
        XCTAssertTrue(coordinator.snapshot.phase.isActive)
        XCTAssertTrue(voiceoverController.isDetailOverlayActive)
    }
}

// MARK: - Test doubles

final class StubVoiceoverRepository: DiscoveryVoiceoverRepository, @unchecked Sendable {
    func fetchVoiceovers(for discoveryIds: [Int64]) async -> [DiscoveryVoiceoverAsset] {
        []
    }

    func requestVoiceover(
        for discoveryId: Int64,
        voiceModelId: String,
        ttsModel: String
    ) async -> DiscoveryVoiceoverAsset {
        DiscoveryVoiceoverAsset(
            discoveryId: discoveryId,
            status: .ready,
            audioURL: nil,
            provider: nil,
            ttsModel: ttsModel,
            voiceModelId: voiceModelId,
            fileName: nil,
            fileExtension: nil,
            requestedAt: nil,
            updatedAt: nil,
            errorReason: nil,
            wasExistingResponse: false,
            wasRefunded: false
        )
    }

    func countUserVoiceovers() async -> Int {
        0
    }
}

