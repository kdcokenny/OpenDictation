import Foundation
import os.log

/// Filters transcription output to remove hallucinations and filler words.
/// Applied automatically after every local transcription.
/// Adapted from VoiceInk/Services/TranscriptionOutputFilter.swift
struct TranscriptionOutputFilter {
    
    private static let logger = Logger.app(category: "TranscriptionOutputFilter")
    
    // MARK: - Patterns
    
    /// Patterns that indicate hallucinations (whisper artifacts)
    private static let hallucinationPatterns = [
        #"\[.*?\]"#,     // [BLANK_AUDIO], [MUSIC], etc.
        #"\(.*?\)"#,     // (music), (laughs), etc.
        #"\{.*?\}"#      // {inaudible}, etc.
    ]
    
    /// Common filler words to remove
    private static let fillerWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "ah", "eh", "hmm", "hm", "mmm", "mm", "mh", "ha", "ehh"
    ]
    
    // MARK: - Public API
    
    /// Filters the transcription text to remove artifacts and filler words.
    /// - Parameter text: Raw transcription text from whisper
    /// - Returns: Cleaned text with hallucinations and fillers removed
    static func filter(_ text: String) -> String {
        var filteredText = text
        
        // Remove <TAG>...</TAG> blocks (XML-like artifacts)
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(
                in: filteredText,
                options: [],
                range: range,
                withTemplate: ""
            )
        }
        
        // Remove bracketed hallucinations
        for pattern in hallucinationPatterns {
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
        
        // Remove filler words (with optional trailing punctuation)
        for fillerWord in fillerWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(
                    in: filteredText,
                    options: [],
                    range: range,
                    withTemplate: ""
                )
            }
        }
        
        // Clean up excessive whitespace
        filteredText = filteredText.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Log if text was modified
        if filteredText != text {
            logger.debug("Filtered transcription: \"\(filteredText)\"")
        }
        
        return filteredText
    }
}
