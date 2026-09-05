import Foundation
import XCTest
@testable import OpenDictation

final class DictationDictionaryTests: XCTestCase {
    func testLiteralReplacementUsesWordBoundariesAndPreservesPunctuation() throws {
        let dictionary = try DictationDictionary(replacements: [
            .init(source: "open ai", replacement: "OpenAI")
        ])

        XCTAssertEqual(
            dictionary.apply(to: "Try open ai, then open airway."),
            "Try OpenAI, then open airway."
        )
    }

    func testLongestReplacementWinsAtSamePosition() throws {
        let dictionary = try DictationDictionary(replacements: [
            .init(source: "New", replacement: "Old"),
            .init(source: "New York", replacement: "NYC")
        ])

        XCTAssertEqual(dictionary.apply(to: "New York and New"), "NYC and Old")
    }

    func testReplacementsDoNotCascade() throws {
        let dictionary = try DictationDictionary(replacements: [
            .init(source: "alpha", replacement: "beta"),
            .init(source: "beta", replacement: "gamma")
        ])

        XCTAssertEqual(dictionary.apply(to: "alpha beta"), "beta gamma")
    }

    func testReplacementTreatsDollarSignLiterally() throws {
        let dictionary = try DictationDictionary(replacements: [
            .init(source: "price", replacement: "$5")
        ])

        XCTAssertEqual(dictionary.apply(to: "The price changed."), "The $5 changed.")
    }

    func testReplacementSupportsUnicodeBoundaries() throws {
        let dictionary = try DictationDictionary(replacements: [
            .init(source: "café", replacement: "Café du Monde")
        ])

        XCTAssertEqual(
            dictionary.apply(to: "A café, not cafés."),
            "A Café du Monde, not cafés."
        )
    }

    func testPunctuationTermDoesNotMatchInsideLongerIdentifier() throws {
        let dictionary = try DictationDictionary(replacements: [
            .init(source: "C++", replacement: "cplusplus")
        ])

        XCTAssertEqual(
            dictionary.apply(to: "C++ and C++17"),
            "cplusplus and C++17"
        )
    }

    func testDuplicateVocabularyFailsCaseInsensitively() {
        XCTAssertThrowsError(try DictationDictionary(vocabulary: ["OpenAI", "openai"])) {
            XCTAssertEqual(
                $0 as? DictationDictionary.ValidationError,
                .duplicateVocabularyEntry("openai")
            )
        }
    }

    func testEmptyReplacementFailsValidation() {
        XCTAssertThrowsError(try DictationDictionary(replacements: [
            .init(source: "", replacement: "OpenAI")
        ])) {
            XCTAssertEqual(
                $0 as? DictationDictionary.ValidationError,
                .emptyReplacementSource
            )
        }
    }

    func testDuplicateReplacementSourceFailsCaseInsensitively() {
        XCTAssertThrowsError(try DictationDictionary(replacements: [
            .init(source: "open ai", replacement: "OpenAI"),
            .init(source: "Open AI", replacement: "OPENAI")
        ])) {
            XCTAssertEqual(
                $0 as? DictationDictionary.ValidationError,
                .duplicateReplacementSource("Open AI")
            )
        }
    }

    func testSaveAndLoadRoundTrip() throws {
        let suiteName = "DictationDictionaryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dictionary = try DictationDictionary(
            vocabulary: ["Parakeet", "María"],
            replacements: [.init(source: "pair a keet", replacement: "Parakeet")]
        )

        try dictionary.save(to: defaults)

        XCTAssertEqual(try DictationDictionary.load(from: defaults), dictionary)
    }

    func testCorruptStorageFailsLoudly() throws {
        let suiteName = "DictationDictionaryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: DictationDictionary.storageKey)

        XCTAssertThrowsError(try DictationDictionary.load(from: defaults)) {
            XCTAssertTrue($0 is DictationDictionary.StorageError)
        }
    }

    func testContextPromptIncludesStoredVocabulary() throws {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: DictationDictionary.storageKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: DictationDictionary.storageKey)
            } else {
                defaults.removeObject(forKey: DictationDictionary.storageKey)
            }
        }
        let dictionary = try DictationDictionary(vocabulary: ["Parakeet", "María"])
        try dictionary.save()

        let prompt = try XCTUnwrap(ContextProfile.prose.whisperPrompt)

        XCTAssertTrue(prompt.contains("Vocabulary: Parakeet, María."))
    }

    func testPromptVocabularyIsCapped() throws {
        let terms = (1...60).map { "term\($0)" }
        let dictionary = try DictationDictionary(vocabulary: terms)

        let promptTerms = try XCTUnwrap(dictionary.promptVocabulary)
            .components(separatedBy: ", ")
        XCTAssertEqual(promptTerms.count, 50)
        XCTAssertLessThanOrEqual(try XCTUnwrap(dictionary.promptVocabulary).count, 500)
    }
}
