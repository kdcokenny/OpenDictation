import Foundation

/// An explicit choice of runtime and model family. Existing installations keep Whisper.
enum LocalSpeechEngine: String, CaseIterable, Sendable {
    case whisper
    case parakeetV2
    case parakeetV3

    var displayName: String {
        switch self {
        case .whisper: return "Whisper"
        case .parakeetV2: return "Parakeet v2 · English"
        case .parakeetV3: return "Parakeet v3 · Multilingual"
        }
    }

    var parakeetVersion: ParakeetModelVersion? {
        switch self {
        case .whisper: return nil
        case .parakeetV2: return .v2
        case .parakeetV3: return .v3
        }
    }

    func supportsLanguage(_ language: String) -> Bool {
        guard !language.isEmpty && language != "auto" else { return true }
        switch self {
        case .whisper: return WhisperLanguages.all[language] != nil
        case .parakeetV2: return language == "en"
        case .parakeetV3: return Self.parakeetLanguages.contains(language)
        }
    }

    // NVIDIA's TDT v3 model card lists these 25 languages, including Maltese.
    static let parakeetLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu",
        "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"
    ]
}
