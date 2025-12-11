import Foundation

/// Quality tiers for local transcription.
/// Apple-style: simple choices without technical details.
enum TranscriptionQuality: String, CaseIterable, Codable {
    case fast = "fast"
    case balanced = "balanced"
    case bestQuality = "bestQuality"
    
    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .bestQuality: return "Best Quality"
        }
    }
    
    var description: String {
        switch self {
        case .fast: return "Fastest. Good for quick notes."
        case .balanced: return "Better accuracy. Good for most tasks."
        case .bestQuality: return "Best accuracy. Great for important documents."
        }
    }
    
    /// Returns the appropriate model name based on quality and language.
    /// Uses .en models for English, multilingual models for other languages.
    func modelName(forLanguage language: String) -> String {
        let isEnglish = language == "en" || language.isEmpty
        
        switch self {
        case .fast:
            return isEnglish ? "ggml-tiny.en" : "ggml-tiny"
        case .balanced:
            return isEnglish ? "ggml-base.en" : "ggml-base"
        case .bestQuality:
            // Large model is always multilingual (no .en variant)
            return "ggml-large-v3-turbo-q5_0"
        }
    }
    
    /// Whether this quality tier is bundled with the app.
    var isBundled: Bool {
        self == .fast
    }
}

/// Curated list of Whisper models.
/// Models are downloaded from Hugging Face.
/// Users don't see these directly - they select Quality + Language instead.
enum PredefinedModels {
    
    /// All available models (internal use)
    static let all: [WhisperModel] = [
        // Fast tier - English
        WhisperModel(
            id: UUID(),
            name: "ggml-tiny.en",
            displayName: "Fast",
            size: "75 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
            isMultilingual: false,
            description: "Fastest. Good for quick notes.",
            isBundled: true
        ),
        
        // Fast tier - Multilingual
        WhisperModel(
            id: UUID(),
            name: "ggml-tiny",
            displayName: "Fast",
            size: "75 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
            isMultilingual: true,
            description: "Fastest. Good for quick notes."
        ),
        
        // Balanced tier - English
        WhisperModel(
            id: UUID(),
            name: "ggml-base.en",
            displayName: "Balanced",
            size: "142 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
            isMultilingual: false,
            description: "Better accuracy. Good for most tasks."
        ),
        
        // Balanced tier - Multilingual
        WhisperModel(
            id: UUID(),
            name: "ggml-base",
            displayName: "Balanced",
            size: "142 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
            isMultilingual: true,
            description: "Better accuracy. Good for most tasks."
        ),
        
        // Best Quality tier - Multilingual only
        WhisperModel(
            id: UUID(),
            name: "ggml-large-v3-turbo-q5_0",
            displayName: "Best Quality",
            size: "547 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
            isMultilingual: true,
            description: "Best accuracy. Great for important documents."
        )
    ]
    
    /// The default bundled model
    static var bundled: WhisperModel {
        guard let model = all.first(where: { $0.isBundled }) else {
            fatalError("PredefinedModels: No model marked as bundled. Ensure at least one WhisperModel has isBundled: true.")
        }
        return model
    }
    
    /// Find a model by name
    static func find(byName name: String) -> WhisperModel? {
        all.first { $0.name == name }
    }
    
    /// Get the model for a quality tier and language
    static func model(for quality: TranscriptionQuality, language: String) -> WhisperModel? {
        let modelName = quality.modelName(forLanguage: language)
        return find(byName: modelName)
    }
}
