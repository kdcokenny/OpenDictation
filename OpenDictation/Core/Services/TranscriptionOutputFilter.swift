import Foundation

/// Removes known speech-to-text control markers from transcription output.
struct TranscriptionOutputFilter {
    static let removeFillerWordsKey = "removeFillerWords"

    private static let artifactNamePattern = #"(?:blank[_ ]audio|music(?: playing)?|applause|laughter|laughs|inaudible|silence|background noise|noise)"#
    private static let whisperControlNamePattern = #"(?:startoftranscript|endoftext|nospeech|notimestamps|translate|transcribe|[0-9]+(?:\.[0-9]+)?)"#
    private static let fillerWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "ah", "eh", "hmm", "hm", "mmm", "mm", "mh", "ehh"
    ]

    /// Applies the user's saved cleanup preference.
    static func filter(_ text: String, defaults: UserDefaults = .standard) -> String {
        filter(
            text,
            removeFillerWords: defaults.bool(forKey: removeFillerWordsKey)
        )
    }

    /// Applies deterministic cleanup without reading storage.
    static func filter(_ text: String, removeFillerWords: Bool) -> String {
        let annotationPattern = #"(?i)(?:\[\s*"# + artifactNamePattern
            + #"\s*\]|\(\s*"# + artifactNamePattern
            + #"\s*\)|\{\s*"# + artifactNamePattern + #"\s*\})"#
        let controlTokenPattern = #"(?i)<\|"# + whisperControlNamePattern + #"\|>"#
        var result = replacingMatches(in: text, pattern: annotationPattern)
        result = replacingMatches(in: result, pattern: controlTokenPattern)

        if removeFillerWords {
            result = removeFillers(from: result)
        }

        guard result != text else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalizeWhitespace(in: result)
    }

    private static func removeFillers(from text: String) -> String {
        let alternatives = fillerWords
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = #"(?i)(?<![\p{L}\p{M}\p{N}_])(?:"#
            + alternatives
            + #")(?![\p{L}\p{M}\p{N}_])[,\.]?"#
        return replacingMatches(in: text, pattern: pattern)
    }

    private static func replacingMatches(in text: String, pattern: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            assertionFailure("Invalid transcription cleanup pattern")
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: ""
        )
    }

    private static func normalizeWhitespace(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(
                of: #"[\t ]{2,}"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
        }

        return lines
            .joined(separator: "\n")
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
