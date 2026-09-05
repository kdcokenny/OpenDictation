import Foundation
import FluidAudio
import os.log
#if canImport(whisper)
import whisper
#endif

/// Thread-safe wrapper for whisper.cpp context.
/// Uses actor pattern to ensure whisper.cpp is only accessed from one thread at a time.
/// Adapted from VoiceInk/Whisper/LibWhisper.swift
actor WhisperContext {
    
    // MARK: - Properties
    
    private nonisolated(unsafe) var context: OpaquePointer?
    private var languageCString: [CChar]?
    private var promptCString: [CChar]?
    private var vadPathCString: [CChar]?
    private var vadModelPath: String?
    
    private let logger = Logger.app(category: "WhisperContext")
    
    // MARK: - Settings
    
    /// Language code for transcription (e.g., "en", "auto")
    var language: String = "auto"
    
    /// Initial prompt to guide transcription
    var initialPrompt: String?
    
    /// Temperature for sampling (0 = deterministic, 1 = more variation)
    var temperature: Float = 0.0
    
    /// Whether to translate to English
    var translateToEnglish: Bool = false
    
    // MARK: - Lifecycle
    
    private init() {}
    
    init(context: OpaquePointer) {
        self.context = context
    }
    
    deinit {
        if let context = context {
            whisper_free(context)
        }
    }
    
    // MARK: - Factory
    
    /// Creates a new WhisperContext by loading a model from the given path.
    static func createContext(path: String) async throws -> WhisperContext {
        let whisperContext = WhisperContext()
        try await whisperContext.initializeModel(path: path)
        
        // Load VAD model from bundle resources
        let vadModelPath = await VADModelManager.shared.getModelPath()
        await whisperContext.setVADModelPath(vadModelPath)
        
        return whisperContext
    }
    
    // MARK: - Configuration
    
    /// Configures transcription parameters.
    /// Must be called before fullTranscribe().
    func configure(
        language: String = "auto",
        temperature: Float = 0.0,
        initialPrompt: String? = nil,
        translateToEnglish: Bool = false
    ) {
        self.language = language
        self.temperature = temperature
        self.initialPrompt = initialPrompt
        self.translateToEnglish = translateToEnglish
    }
    
    // MARK: - Transcription
    
    /// Performs full transcription on the provided audio samples.
    /// - Parameter samples: Float32 audio samples (16kHz, mono)
    /// - Returns: true if transcription succeeded, false otherwise
    func fullTranscribe(samples: [Float]) async throws -> Bool {
        let cancellationState = WhisperCancellationState()
        return try await withTaskCancellationHandler {
            if Task.isCancelled {
                cancellationState.cancel()
            }
            return try runFullTranscription(
                samples: samples,
                cancellationState: cancellationState
            )
        } onCancel: {
            cancellationState.cancel()
        }
    }

    private func runFullTranscription(
        samples: [Float],
        cancellationState: WhisperCancellationState
    ) throws -> Bool {
        guard let context = context else {
            logger.error("No whisper context available")
            return false
        }
        
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Set language
        if language != "auto" {
            languageCString = Array(language.utf8CString)
            params.language = languageCString?.withUnsafeBufferPointer { $0.baseAddress }
        } else {
            languageCString = nil
            params.language = nil
        }
        
        // Set initial prompt
        if let prompt = initialPrompt, !prompt.isEmpty {
            promptCString = Array(prompt.utf8CString)
            params.initial_prompt = promptCString?.withUnsafeBufferPointer { $0.baseAddress }
        } else {
            promptCString = nil
            params.initial_prompt = nil
        }
        
        // Configure parameters
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = translateToEnglish
        params.n_threads = Int32(maxThreads)
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false
        params.temperature = temperature

        let cancellationPointer = Unmanaged.passRetained(cancellationState).toOpaque()
        defer {
            Unmanaged<WhisperCancellationState>
                .fromOpaque(cancellationPointer)
                .release()
        }
        params.abort_callback_user_data = cancellationPointer
        params.abort_callback = { userData in
            guard let userData else { return false }
            let state = Unmanaged<WhisperCancellationState>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return state.isCancelled
        }
        
        whisper_reset_timings(context)
        
        // Configure VAD if model is available
        if let vadModelPath = self.vadModelPath {
            vadPathCString = Array(vadModelPath.utf8CString)
            params.vad = true
            params.vad_model_path = vadPathCString?.withUnsafeBufferPointer { $0.baseAddress }
            
            var vadParams = whisper_vad_default_params()
            vadParams.threshold = 0.50
            vadParams.min_speech_duration_ms = 250
            vadParams.min_silence_duration_ms = 100
            vadParams.max_speech_duration_s = Float.greatestFiniteMagnitude
            vadParams.speech_pad_ms = 30
            vadParams.samples_overlap = 0.1
            params.vad_params = vadParams
            
            logger.debug("VAD enabled with threshold 0.50")
        } else {
            vadPathCString = nil
            params.vad = false
            logger.debug("VAD disabled (no model path)")
        }
        
        // Run transcription
        let success = whisper_full(context, params, samples, Int32(samples.count)) == 0
        if !success {
            logger.error("Failed to run whisper_full")
        }
        
        // Clear C strings
        languageCString = nil
        promptCString = nil
        vadPathCString = nil

        if cancellationState.isCancelled {
            throw CancellationError()
        }
        
        return success
    }
    
    /// Gets the transcription result from the last fullTranscribe call.
    func getTranscription() -> String {
        guard let context = context else { return "" }
        
        var transcription = ""
        let segmentCount = whisper_full_n_segments(context)
        
        for i in 0..<segmentCount {
            if let text = whisper_full_get_segment_text(context, i) {
                transcription += String(cString: text)
            }
        }
        
        return transcription
    }
    
    /// Releases all resources held by this context.
    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        languageCString = nil
        promptCString = nil
        vadPathCString = nil
        logger.debug("Whisper context resources released")
    }
    
    // MARK: - Private
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        
        #if targetEnvironment(simulator)
        params.use_gpu = false
        logger.info("Running on simulator, using CPU")
        #else
        params.flash_attn = true
        logger.info("Flash attention enabled for Metal")
        #endif
        
        guard let context = whisper_init_from_file_with_params(path, params) else {
            logger.error("Failed to load model at \(path)")
            throw WhisperError.modelLoadFailed
        }
        
        self.context = context
        logger.info("Model loaded successfully from \(path)")
    }
    
    private func setVADModelPath(_ path: String?) {
        self.vadModelPath = path
        if path != nil {
            logger.debug("VAD model path set")
        }
    }
}

// MARK: - Helpers

private func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}

/// Thread-safe state shared with whisper.cpp's C abort callback.
/// `runFullTranscription` retains it until `whisper_full` returns.
final class WhisperCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

// MARK: - Audio Loading

/// Loads any AVFoundation-supported audio file as 16 kHz mono Float32 samples.
func loadAudioSamples(from url: URL) throws -> [Float] {
    let samples: [Float]
    do {
        samples = try AudioConverter().resampleAudioFile(url)
    } catch {
        throw WhisperError.audioLoadFailed
    }

    guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else {
        throw WhisperError.audioLoadFailed
    }

    return samples
}
