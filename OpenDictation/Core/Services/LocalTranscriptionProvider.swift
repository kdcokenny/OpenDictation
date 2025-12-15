import Foundation
import os.log

/// Local transcription provider using whisper.cpp.
/// Performs offline transcription using the selected Whisper model.
/// Uses actor isolation to meet whisper.cpp constraint: don't access from more than one thread at a time.
/// Adapted from VoiceInk/Services/LocalTranscriptionService.swift
actor LocalTranscriptionProvider: TranscriptionProvider {
    
    // MARK: - Singleton
    
    static let shared = LocalTranscriptionProvider()
    
    // MARK: - Properties
    
    private let logger = Logger.app(category: "LocalTranscriptionProvider")
    
    /// The currently loaded whisper context
    private var whisperContext: WhisperContext?
    
    /// The name of the currently loaded model
    private var loadedModelName: String?
    
    private init() {}
    
    // MARK: - TranscriptionProvider
    
    /// Transcribes the audio file at the given URL using the local Whisper model.
    func transcribe(audioURL: URL) async throws -> String {
        // Get selected model from ModelManager, with fallback to any available model
        let modelManager = await ModelManager.shared
        
        let selectedModel = await resolveAvailableModel(modelManager: modelManager)
        guard let selectedModel else {
            logger.error("No speech models available")
            throw WhisperError.modelNotFound
        }
        
        // Load model if needed (different model or not loaded)
        if loadedModelName != selectedModel.name || whisperContext == nil {
            try await loadModel(selectedModel)
        }
        
        guard let context = whisperContext else {
            logger.error("Whisper context not available after load")
            throw WhisperError.modelLoadFailed
        }
        
        // Configure transcription parameters from UserDefaults
        // Use shared "language" key (same as cloud mode) for consistency
        let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
        // Local mode uses deterministic transcription (temperature = 0)
        let temperature: Float = 0.0
        // No initial prompt for local mode (keep transcription clean)
        let initialPrompt: String? = nil
        // No translation - user selects language directly
        let translateToEnglish = false
        
        await context.configure(
            language: language,
            temperature: temperature,
            initialPrompt: initialPrompt,
            translateToEnglish: translateToEnglish
        )
        
        // Load audio samples from file
        logger.info("Loading audio from \(audioURL.lastPathComponent)")
        let samples: [Float]
        do {
            samples = try loadAudioSamples(from: audioURL)
        } catch {
            logger.error("Failed to load audio: \(error.localizedDescription)")
            throw WhisperError.audioLoadFailed
        }
        
        guard !samples.isEmpty else {
            logger.error("Audio file produced no samples")
            throw WhisperError.audioLoadFailed
        }
        
        logger.info("Loaded \(samples.count) audio samples, starting transcription")
        
        // Run transcription
        let success = await context.fullTranscribe(samples: samples)
        
        guard success else {
            logger.error("Whisper transcription failed")
            throw WhisperError.transcriptionFailed
        }
        
        // Get result
        let rawText = await context.getTranscription()
        
        logger.info("Transcription complete: \(rawText.prefix(50))...")
        
        // Apply output filter to remove hallucinations and filler words
        let filteredText = TranscriptionOutputFilter.filter(rawText)
        
        return filteredText
    }
    
    // MARK: - Model Management
    
    /// Loads a Whisper model from disk.
    private func loadModel(_ model: DownloadedModel) async throws {
        logger.info("Loading model: \(model.name)")
        
        // Release existing context
        await releaseContext()
        
        // Create new context
        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)
            loadedModelName = model.name
            logger.info("Model \(model.name) loaded successfully")
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription)")
            whisperContext = nil
            loadedModelName = nil
            throw error
        }
    }
    
    /// Releases the current whisper context to free memory.
    func releaseContext() async {
        if let context = whisperContext {
            await context.releaseResources()
        }
        whisperContext = nil
        loadedModelName = nil
        logger.debug("Whisper context released")
    }
    
    // MARK: - Model Resolution
    
    /// Resolves the model to use for transcription, with graceful fallback.
    /// Apple philosophy: always try to find a working model rather than failing.
    ///
    /// Priority:
    /// 1. Selected model (if downloaded)
    /// 2. Bundled model (ggml-tiny)
    /// 3. Any downloaded model
    /// 4. nil (no models available)
    private func resolveAvailableModel(modelManager: ModelManager) async -> DownloadedModel? {
        // First try: selected model
        if let selected = await modelManager.selectedModel {
            return selected
        }
        
        let downloadedModels = await modelManager.downloadedModels
        
        // Second try: bundled model
        let bundledName = PredefinedModels.bundled.name
        if let bundled = downloadedModels.first(where: { $0.name == bundledName }) {
            logger.info("Selected model not available, falling back to bundled: \(bundledName)")
            await MainActor.run {
                modelManager.selectedModelName = bundledName
            }
            return bundled
        }
        
        // Third try: any available model
        if let anyModel = downloadedModels.first {
            logger.info("Bundled model not available, falling back to: \(anyModel.name)")
            await MainActor.run {
                modelManager.selectedModelName = anyModel.name
            }
            return anyModel
        }
        
        // No models available
        logger.warning("No speech models available for transcription")
        return nil
    }
}
