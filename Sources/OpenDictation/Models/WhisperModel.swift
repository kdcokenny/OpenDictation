import Foundation

/// Represents a downloadable Whisper model for local transcription.
/// Adapted from VoiceInk/Models/TranscriptionModel.swift
struct WhisperModel: Identifiable, Equatable, Codable {
    
    /// Unique identifier
    let id: UUID
    
    /// Internal name (e.g., "ggml-tiny.en")
    let name: String
    
    /// Display name for UI (e.g., "Tiny (English)")
    let displayName: String
    
    /// Human-readable size (e.g., "75 MB")
    let size: String
    
    /// Download URL from Hugging Face
    let downloadURL: String
    
    /// Whether this model supports multiple languages
    let isMultilingual: Bool
    
    /// Short description of the model
    let description: String
    
    /// Whether this model came from the app bundle (vs downloaded)
    var isBundled: Bool = false
    
    // MARK: - Computed Properties
    
    /// The filename for this model (e.g., "ggml-tiny.en.bin")
    var filename: String {
        "\(name).bin"
    }
    
    /// Languages this model supports.
    /// Multilingual models support all Whisper languages.
    /// English-only models (.en suffix) only support English.
    var supportedLanguages: [String: String] {
        isMultilingual ? WhisperLanguages.all : WhisperLanguages.englishOnly
    }
    
    /// Checks if this model supports a given language code.
    /// - Parameter languageCode: ISO 639-1 code (e.g., "en", "es") or "auto"
    /// - Returns: true if model can transcribe this language well
    func supportsLanguage(_ languageCode: String) -> Bool {
        // "auto" is supported by all models (they'll detect the language)
        // But for English-only models, auto will still only work for English
        if languageCode == "auto" {
            return true  // Let user try auto on any model
        }
        return supportedLanguages.keys.contains(languageCode)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: WhisperModel, rhs: WhisperModel) -> Bool {
        lhs.name == rhs.name
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, size, downloadURL, isMultilingual, description, isBundled
    }
}

/// Represents a downloaded model on disk.
struct DownloadedModel: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
    let isBundled: Bool
    
    static func == (lhs: DownloadedModel, rhs: DownloadedModel) -> Bool {
        lhs.name == rhs.name
    }
}

/// Language dictionaries for Whisper models.
enum WhisperLanguages {
    
    /// English only (for .en models)
    static let englishOnly: [String: String] = [
        "en": "English"
    ]
    
    /// All supported languages (for multilingual models)
    static let all: [String: String] = [
        "auto": "Auto-detect",
        "af": "Afrikaans",
        "ar": "Arabic",
        "be": "Belarusian",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "ca": "Catalan",
        "cs": "Czech",
        "cy": "Welsh",
        "da": "Danish",
        "de": "German",
        "el": "Greek",
        "en": "English",
        "es": "Spanish",
        "et": "Estonian",
        "fa": "Persian",
        "fi": "Finnish",
        "fr": "French",
        "gl": "Galician",
        "gu": "Gujarati",
        "he": "Hebrew",
        "hi": "Hindi",
        "hr": "Croatian",
        "hu": "Hungarian",
        "id": "Indonesian",
        "is": "Icelandic",
        "it": "Italian",
        "ja": "Japanese",
        "kk": "Kazakh",
        "ko": "Korean",
        "lt": "Lithuanian",
        "lv": "Latvian",
        "mk": "Macedonian",
        "ml": "Malayalam",
        "mr": "Marathi",
        "ms": "Malay",
        "ne": "Nepali",
        "nl": "Dutch",
        "no": "Norwegian",
        "pl": "Polish",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sk": "Slovak",
        "sl": "Slovenian",
        "sq": "Albanian",
        "sr": "Serbian",
        "sv": "Swedish",
        "sw": "Swahili",
        "ta": "Tamil",
        "te": "Telugu",
        "th": "Thai",
        "tl": "Tagalog",
        "tr": "Turkish",
        "uk": "Ukrainian",
        "ur": "Urdu",
        "vi": "Vietnamese",
        "zh": "Chinese"
    ]
}
