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

    func testPreservesFillersByDefaultBehavior() {
        let text = "Um, I think, uh, this works."

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: false),
            text
        )
    }

    func testStaticFilterPreservesFillersWhenPreferenceIsUnset() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: TranscriptionOutputFilter.removeFillerWordsKey)
        defaults.removeObject(forKey: TranscriptionOutputFilter.removeFillerWordsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: TranscriptionOutputFilter.removeFillerWordsKey)
            } else {
                defaults.removeObject(forKey: TranscriptionOutputFilter.removeFillerWordsKey)
            }
        }

        XCTAssertEqual(TranscriptionOutputFilter.filter("Um, keep this."), "Um, keep this.")
    }

    func testStaticFilterReadsEnabledPreference() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: TranscriptionOutputFilter.removeFillerWordsKey)
        defaults.set(true, forKey: TranscriptionOutputFilter.removeFillerWordsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: TranscriptionOutputFilter.removeFillerWordsKey)
            } else {
                defaults.removeObject(forKey: TranscriptionOutputFilter.removeFillerWordsKey)
            }
        }

        XCTAssertEqual(TranscriptionOutputFilter.filter("Um, remove this."), "remove this.")
    }

    func testRemovesFillersWhenEnabledWithoutMatchingInsideWords() {
        let text = "Um, the album and hummus, uh, remain."

        XCTAssertEqual(
            TranscriptionOutputFilter.filter(text, removeFillerWords: true),
            "the album and hummus, remain."
        )
    }
}
