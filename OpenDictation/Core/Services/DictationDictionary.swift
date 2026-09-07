import Foundation

/// User-defined terms and literal transcript replacements.
struct DictationDictionary: Equatable, Sendable {
    struct Replacement: Codable, Equatable, Sendable {
        let source: String
        let replacement: String
    }

    enum ValidationError: LocalizedError, Equatable {
        case emptyVocabularyEntry
        case duplicateVocabularyEntry(String)
        case tooManyVocabularyEntries(Int)
        case vocabularyEntryTooLong(String)
        case emptyReplacementSource
        case emptyReplacementValue(String)
        case duplicateReplacementSource(String)
        case tooManyReplacements(Int)
        case replacementSourceTooLong(String)
        case replacementValueTooLong(String)
        case invalidLineBreak(String)

        var errorDescription: String? {
            switch self {
            case .emptyVocabularyEntry:
                return "Vocabulary entries cannot be empty."
            case .duplicateVocabularyEntry(let entry):
                return "Vocabulary contains a duplicate: \(entry)"
            case .tooManyVocabularyEntries(let maximum):
                return "Vocabulary is limited to \(maximum) entries."
            case .vocabularyEntryTooLong(let entry):
                return "Vocabulary entry is too long: \(entry)"
            case .emptyReplacementSource:
                return "Enter the text to replace."
            case .emptyReplacementValue(let source):
                return "Enter a replacement for \(source)."
            case .duplicateReplacementSource(let source):
                return "Replacement source is duplicated: \(source)"
            case .tooManyReplacements(let maximum):
                return "Replacements are limited to \(maximum) entries."
            case .replacementSourceTooLong(let source):
                return "Replacement source is too long: \(source)"
            case .replacementValueTooLong(let source):
                return "Replacement for \(source) is too long."
            case .invalidLineBreak(let value):
                return "Entries must stay on one line: \(value)"
            }
        }
    }

    enum StorageError: LocalizedError {
        case unreadableData

        var errorDescription: String? {
            "The saved dictionary could not be read. Saving will replace it."
        }
    }

    static let storageKey = "dictationDictionary"
    static let maximumVocabularyEntries = 100
    static let maximumReplacements = 100

    private static let maximumEntryLength = 200
    private static let promptTermLimit = 50
    private static let promptCharacterLimit = 500

    let vocabulary: [String]
    let replacements: [Replacement]

    init(vocabulary: [String] = [], replacements: [Replacement] = []) throws {
        guard vocabulary.count <= Self.maximumVocabularyEntries else {
            throw ValidationError.tooManyVocabularyEntries(Self.maximumVocabularyEntries)
        }
        guard replacements.count <= Self.maximumReplacements else {
            throw ValidationError.tooManyReplacements(Self.maximumReplacements)
        }

        self.vocabulary = try Self.validateVocabulary(vocabulary)
        self.replacements = try Self.validateReplacements(replacements)
    }

    static func load(from defaults: UserDefaults = .standard) throws -> DictationDictionary {
        guard let data = defaults.data(forKey: storageKey) else {
            return try DictationDictionary()
        }

        guard let decoded = try? JSONDecoder().decode(StoredDictionary.self, from: data) else {
            throw StorageError.unreadableData
        }

        return try DictationDictionary(
            vocabulary: decoded.vocabulary,
            replacements: decoded.replacements
        )
    }

    func save(to defaults: UserDefaults = .standard) throws {
        let stored = StoredDictionary(vocabulary: vocabulary, replacements: replacements)
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Applies every replacement once against the original transcript.
    func apply(to text: String) -> String {
        guard !replacements.isEmpty else {
            return text
        }

        let ordered = replacements.sorted {
            $0.source.utf16.count > $1.source.utf16.count
        }
        let alternatives = ordered.map { replacement in
            Self.boundedPattern(for: replacement.source)
        }
        let pattern = alternatives.map { "(\($0))" }.joined(separator: "|")

        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            assertionFailure("Dictionary replacement pattern is invalid")
            return text
        }

        let mutableText = NSMutableString(string: text)
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )

        for match in matches.reversed() {
            guard let replacementIndex = (1...ordered.count).first(where: {
                match.range(at: $0).location != NSNotFound
            }) else {
                continue
            }

            mutableText.replaceCharacters(
                in: match.range,
                with: ordered[replacementIndex - 1].replacement
            )
        }

        return mutableText as String
    }

    /// A bounded vocabulary hint suitable for Whisper-compatible prompt fields.
    var promptVocabulary: String? {
        var terms: [String] = []
        var characterCount = 0

        for term in vocabulary.prefix(Self.promptTermLimit) {
            let separatorLength = terms.isEmpty ? 0 : 2
            guard characterCount + separatorLength + term.count <= Self.promptCharacterLimit else {
                break
            }
            terms.append(term)
            characterCount += separatorLength + term.count
        }

        guard !terms.isEmpty else {
            return nil
        }
        return terms.joined(separator: ", ")
    }

    private static func validateVocabulary(_ entries: [String]) throws -> [String] {
        var seen = Set<String>()
        return try entries.map { rawEntry in
            let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else {
                throw ValidationError.emptyVocabularyEntry
            }
            try validateSingleLine(entry)
            guard entry.count <= maximumEntryLength else {
                throw ValidationError.vocabularyEntryTooLong(entry)
            }

            let duplicateKey = entry.lowercased()
            guard seen.insert(duplicateKey).inserted else {
                throw ValidationError.duplicateVocabularyEntry(entry)
            }
            return entry
        }
    }

    private static func validateReplacements(_ entries: [Replacement]) throws -> [Replacement] {
        var seenSources = Set<String>()
        return try entries.map { rawEntry in
            let source = rawEntry.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = rawEntry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !source.isEmpty else {
                throw ValidationError.emptyReplacementSource
            }
            guard !replacement.isEmpty else {
                throw ValidationError.emptyReplacementValue(source)
            }
            try validateSingleLine(source)
            try validateSingleLine(replacement)
            guard source.count <= maximumEntryLength else {
                throw ValidationError.replacementSourceTooLong(source)
            }
            guard replacement.count <= maximumEntryLength else {
                throw ValidationError.replacementValueTooLong(source)
            }

            let duplicateKey = source.lowercased()
            guard seenSources.insert(duplicateKey).inserted else {
                throw ValidationError.duplicateReplacementSource(source)
            }
            return Replacement(source: source, replacement: replacement)
        }
    }

    private static func validateSingleLine(_ value: String) throws {
        guard !value.contains(where: { $0.isNewline }) else {
            throw ValidationError.invalidLineBreak(value)
        }
    }

    private static func boundedPattern(for source: String) -> String {
        let escapedSource = NSRegularExpression.escapedPattern(for: source)
        return #"(?<![\p{L}\p{M}\p{N}_])"#
            + escapedSource
            + #"(?![\p{L}\p{M}\p{N}_])"#
    }
}

private struct StoredDictionary: Codable {
    let vocabulary: [String]
    let replacements: [DictationDictionary.Replacement]
}
