import XCTest
@testable import WhatsThatData

final class SupabaseVoiceoverRepositoryTests: XCTestCase {
    private let models = [
        "kittentts-nano-0.2-expr-voice-3-m",
        "kittentts-nano-0.1-expr-voice-3-m",
        "kittentts-0.1.0-expr-voice-4-m"
    ]
    private let audioExtension = ".wav"
    private let timingExtension = ".json"

    func testResolverSelectsPreferredModelInOrder() {
        let available = [
            "kittentts-nano-0.1-expr-voice-3-m.wav",
            "kittentts-0.1.0-expr-voice-4-m.wav",
            "note.txt"
        ]

        let result = VoiceoverAssetResolver.resolve(
            availableFileNames: available,
            voiceoverModels: models,
            audioExtension: audioExtension,
            timingExtension: timingExtension
        )

        XCTAssertEqual(result.audioFileName, "kittentts-nano-0.1-expr-voice-3-m.wav")
        XCTAssertEqual(result.modelIdentifier, "kittentts-nano-0.1-expr-voice-3-m")
        XCTAssertEqual(result.timingFileName, "kittentts-nano-0.1-expr-voice-3-m.json")
    }

    func testResolverFallsBackToAnyWaveFile() {
        let available = [
            "custom-voice.wav",
            "custom-voice.json"
        ]

        let result = VoiceoverAssetResolver.resolve(
            availableFileNames: available,
            voiceoverModels: models,
            audioExtension: audioExtension,
            timingExtension: timingExtension
        )

        XCTAssertEqual(result.audioFileName, "custom-voice.wav")
        XCTAssertNil(result.modelIdentifier)
        XCTAssertEqual(result.timingFileName, "custom-voice.json")
    }

    func testResolverHandlesMissingAudio() {
        let available = [
            "metadata.json",
            "readme.txt"
        ]

        let result = VoiceoverAssetResolver.resolve(
            availableFileNames: available,
            voiceoverModels: models,
            audioExtension: audioExtension,
            timingExtension: timingExtension
        )

        XCTAssertNil(result.audioFileName)
        XCTAssertNil(result.modelIdentifier)
        XCTAssertNil(result.timingFileName)
    }
}
