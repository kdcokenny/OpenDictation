import XCTest
@testable import OpenDictation

final class TranscriptPostProcessorTests: XCTestCase {

    func testArtifactFilterPreservesCodeAndLiteralText() {
        let input = #"Call transcribe(audioURL:context:) with array[index] and { "key": "value" }."#

        XCTAssertEqual(TranscriptionOutputFilter.filter(input), input)
    }

    func testArtifactFilterRemovesOnlyKnownStandaloneArtifacts() {
        let input = "Hello [BLANK_AUDIO] world (music)"

        XCTAssertEqual(TranscriptionOutputFilter.filter(input), "Hello world")
    }

    func testDeterministicCleanerRemovesRepeatedPhrase() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "tell Sarah the onboarding flow the onboarding flow should be behind a feature flag",
            context: context
        )

        XCTAssertEqual(output, "tell Sarah the onboarding flow should be behind a feature flag.")
    }

    func testLiteralScratchThatIsPreserved() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "write the phrase scratch that in the release notes",
            context: context
        )

        XCTAssertEqual(output, "write the phrase scratch that in the release notes.")
    }

    func testScratchThatCommandDropsAbandonedPrefix() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "send the draft tonight scratch that send the draft monday morning after I reread it",
            context: context
        )

        XCTAssertEqual(output, "send the draft monday morning after I reread it.")
    }

    func testPostProcessorReturnsStructuredMetadata() async {
        let processor = TranscriptPostProcessor(modelRegistry: CleanupModelRegistry())
        let transcription = TranscriptionProviderResult(
            rawText: "um we should keep the settings simple",
            metadata: TranscriptionMetadata(provider: .local, speechModelID: "test-model", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(result.finalText, "we should keep the settings simple.")
        XCTAssertEqual(result.route, .deterministic)
        XCTAssertEqual(result.fallbackReason, .deterministicOnly)
        XCTAssertNil(result.modelID)
    }
}
