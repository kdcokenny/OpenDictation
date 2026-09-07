import Foundation

/// Curated list of Whisper models.
/// Models are downloaded from Hugging Face.
/// Users don't see these directly - they select Quality + Language instead.
enum PredefinedModels {
    
    /// All available models (internal use)
    static let all: [WhisperModel] = [
        // Fast tier - Multilingual (bundled - works for all languages)
        WhisperModel(
            id: UUID(),
            name: "ggml-tiny",
            displayName: "Tiny (Multilingual)",
            size: "75 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.bin",
            expectedByteCount: 77_691_713,
            sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            isMultilingual: true,
            description: "Fastest. Works with all languages.",
            isBundled: true
        ),
        
        // Fast tier - English only
        WhisperModel(
            id: UUID(),
            name: "ggml-tiny.en",
            displayName: "Tiny (English)",
            size: "75 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.en.bin",
            expectedByteCount: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
            isMultilingual: false,
            description: "Fastest. Optimized for English."
        ),
        
        // Balanced tier - English
        WhisperModel(
            id: UUID(),
            name: "ggml-base.en",
            displayName: "Balanced",
            size: "142 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en.bin",
            expectedByteCount: 147_964_211,
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
            isMultilingual: false,
            description: "Better accuracy. Good for most tasks."
        ),
        
        // Balanced tier - Multilingual
        WhisperModel(
            id: UUID(),
            name: "ggml-base",
            displayName: "Balanced",
            size: "142 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin",
            expectedByteCount: 147_951_465,
            sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            isMultilingual: true,
            description: "Better accuracy. Good for most tasks."
        ),
        
        // Best Quality tier - Multilingual only
        WhisperModel(
            id: UUID(),
            name: "ggml-large-v3-turbo-q5_0",
            displayName: "Best Quality",
            size: "547 MB",
            downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin",
            expectedByteCount: 574_041_195,
            sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
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
    
    // MARK: - Language-Aware Recommendations
    
    /// Model tiers for capability-based selection
    enum ModelTier: String {
        case tiny
        case base
        case large
    }
    
    /// Returns the recommended model for a language and hardware tier.
    /// Uses English-optimized models when appropriate, multilingual otherwise.
    ///
    /// - Parameters:
    ///   - language: ISO 639-1 language code (e.g., "en", "es") or "auto"
    ///   - tier: Hardware capability tier (tiny/base/large)
    /// - Returns: The best model for this combination
    static func recommendedModel(forLanguage language: String, tier: ModelTier) -> WhisperModel {
        let useEnglishOptimized = (language == "en")
        
        switch tier {
        case .tiny:
            // Tiny tier: use .en for English, multilingual otherwise
            if useEnglishOptimized {
                return find(byName: "ggml-tiny.en") ?? bundled
            } else {
                return find(byName: "ggml-tiny") ?? bundled
            }
            
        case .base:
            // Base tier: use .en for English, multilingual otherwise
            if useEnglishOptimized {
                return find(byName: "ggml-base.en") ?? bundled
            } else {
                return find(byName: "ggml-base") ?? bundled
            }
            
        case .large:
            // Large tier: always multilingual (no .en variant for large-v3-turbo)
            return find(byName: "ggml-large-v3-turbo-q5_0") ?? bundled
        }
    }
}
