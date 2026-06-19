import Foundation
import os.log

/// Filters only high-confidence speech recognition artifacts.
/// Higher-level filler and grammar cleanup belongs in `TranscriptPostProcessor`.
/// Adapted from VoiceInk/Services/TranscriptionOutputFilter.swift
struct TranscriptionOutputFilter {
    
    private static let logger = Logger.app(category: "TranscriptionOutputFilter")
    
    // MARK: - Patterns
    
    /// Known standalone artifacts emitted by speech models.
    private static let artifactTokens = [
        "[BLANK_AUDIO]",
        "[MUSIC]",
        "[NOISE]",
        "[SILENCE]",
        "[LAUGHTER]",
        "[INAUDIBLE]",
        "(music)",
        "(noise)",
        "(silence)",
        "(laughter)",
        "(inaudible)"
    ]
    
    // MARK: - Public API
    
    /// Filters the transcription text to remove high-confidence artifacts.
    /// - Parameter text: Raw transcription text from whisper
    /// - Returns: Text with standalone ASR artifacts removed.
    static func filter(_ text: String) -> String {
        var filteredText = text

        for token in artifactTokens {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            let pattern = #"(?i)(^|\s)\#(escaped)(?=\s|$)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(
                    in: filteredText,
                    options: [],
                    range: range,
                    withTemplate: ""
                )
            }
        }

        filteredText = filteredText.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        if filteredText != text {
            logger.debug("Removed high-confidence speech artifacts")
        }

        return filteredText
    }
}
