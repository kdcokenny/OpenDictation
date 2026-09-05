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
    func transcribe(audioURL: URL, context: ContextProfile) async throws -> String {
        // Use the model the user selected. A missing selection is an actionable error.
        let modelManager = await ModelManager.shared
        
        guard let selectedModel = await modelManager.selectedModel else {
            logger.error("Selected speech model is not available")
            throw WhisperError.modelNotFound
        }
        
        // Load model if needed (different model or not loaded)
        if loadedModelName != selectedModel.name || whisperContext == nil {
            try await loadModel(selectedModel)
        }
        
        guard let modelContext = whisperContext else {
            logger.error("Whisper context not available after load")
            throw WhisperError.modelLoadFailed
        }
        
        // Configure transcription parameters from UserDefaults
        // Use shared "language" key (same as cloud mode) for consistency
        let storedLanguage = UserDefaults.standard.string(forKey: "language") ?? "auto"
        let language = storedLanguage.isEmpty ? "auto" : storedLanguage
        // Local mode uses deterministic transcription (temperature = 0)
        let temperature: Float = 0.0
        // Use pre-captured context (passed from boundary)
        let initialPrompt: String? = context.whisperPrompt
        // No translation - user selects language directly
        let translateToEnglish = false
        
        await modelContext.configure(
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
        let success = try await modelContext.fullTranscribe(samples: samples)
        
        guard success else {
            logger.error("Whisper transcription failed")
            throw WhisperError.transcriptionFailed
        }
        
        // Get result
        let rawText = await modelContext.getTranscription()
        
        logger.info("Whisper transcription completed")
        return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Loads the selected installed model without changing the selection or downloading.
    func prewarmIfInstalled() async throws {
        let modelManager = await ModelManager.shared
        guard let selectedModel = await modelManager.selectedModel else {
            throw WhisperError.modelNotFound
        }

        guard loadedModelName != selectedModel.name || whisperContext == nil else {
            return
        }

        try await loadModel(selectedModel)
    }
}
