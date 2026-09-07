import Foundation
import XCTest
@testable import OpenDictation

final class TranscriptionOutputFilterTests: XCTestCase {
    func testRemovesKnownArtifactAnnotations() {
        let text = "Hello [BLANK_AUDIO] (music) {inaudible} world"

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: false),
            "Hello world"
        )
    }

    func testRemovesWhisperControlTokens() {
        let text = "<|startoftranscript|>Hello<|12.50|> world<|endoftext|>"

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: false),
            "Hello world"
        )
    }

    func testPreservesValidDelimitedTextAndXML() {
        let text = "Jane (CEO) uses [María], Array[String], {braces}, and <person>María</person>."

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: false),
            text
        )
    }

    func testPreservesFillersWhenRemovalIsDisabled() {
        let text = "Um, I think, uh, this works."

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: false),
            text
        )
    }

    func testStoredPreferenceDefaultsToPreservingFillers() throws {
        let suiteName = "TranscriptionOutputFilterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Um, keep this.", defaults: defaults),
            "Um, keep this."
        )
    }

    func testStoredPreferenceEnablesFillerRemoval() throws {
        let suiteName = "TranscriptionOutputFilterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: TranscriptionOutputFilter.removeFillerWordsKey)

        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Um, remove this.", defaults: defaults),
            "remove this."
        )
    }

    func testRemovesFillersWhenEnabledWithoutMatchingInsideWords() {
        let text = "Um, the album and hummus, uh, remain."

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: true),
            "the album and hummus, remain."
        )
    }

    func testPreservesMultilineIndentationWhenNoCleanupMatches() {
        let text = "First line\n    indented with spaces\n\tindented with a tab"

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: false),
            text
        )
    }
}
