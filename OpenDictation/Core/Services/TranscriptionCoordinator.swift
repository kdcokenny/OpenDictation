import Foundation
import os.log

/// Coordinates transcription between local and cloud providers.
/// Selects the appropriate provider based on user settings.
actor TranscriptionCoordinator {
    
    // MARK: - Singleton
    
    static let shared = TranscriptionCoordinator()
    
    // MARK: - Properties
    
    private let logger = Logger.app(category: "TranscriptionCoordinator")
    
    /// The local transcription provider
    private let localProvider = LocalTranscriptionProvider.shared
    
    /// The cloud transcription provider
    private let cloudProvider = CloudTranscriptionProvider.shared
    
    private init() {}
    
    // MARK: - Mode Access
    
    /// Returns the current transcription mode from UserDefaults.
    /// UserDefaults is thread-safe, so this computed property is safe to call from any context.
    nonisolated var currentMode: TranscriptionMode {
        let rawValue = UserDefaults.standard.string(forKey: "transcriptionMode") ?? TranscriptionMode.local.rawValue
        return TranscriptionMode(rawValue: rawValue) ?? .local
    }
    
    /// Sets the transcription mode.
    nonisolated func setMode(_ mode: TranscriptionMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "transcriptionMode")
    }
    
    // MARK: - Transcription
    
    /// Transcribes audio using the current mode's provider.
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - context: The pre-captured context profile
    /// - Returns: The transcribed text
    func transcribe(audioURL: URL, context: ContextProfile) async throws -> String {
        try await transcribePipeline(audioURL: audioURL, context: context).finalText
    }

    /// Runs transcription and local transcript cleanup as one pipeline.
    /// Cleanup never streams partial model output into the delivered text.
    func transcribePipeline(audioURL: URL, context: ContextProfile) async throws -> DictationPipelineResult {
        let mode = currentMode
        logger.info("Transcribing with \(mode.rawValue) mode, context: \(String(describing: context))")

        let transcription: TranscriptionProviderResult
        switch mode {
        case .local:
            transcription = try await localProvider.transcribeResult(audioURL: audioURL, context: context)
        case .cloud:
            transcription = try await cloudProvider.transcribeResult(audioURL: audioURL, context: context)
        }

        let cleanupContext = CleanupContextSnapshot.capture(profile: context)
        let cleanup = await TranscriptPostProcessor.shared.process(
            transcription: transcription,
            context: cleanupContext
        )

        return DictationPipelineResult(
            finalText: cleanup.finalText,
            transcription: transcription,
            cleanup: cleanup
        )
    }
    
    // MARK: - Validation
    
    /// Checks if the current mode is properly configured.
    /// - Returns: nil if valid, or an error message describing the issue
    func validateCurrentMode() async -> String? {
        switch currentMode {
        case .local:
            // Check if a model is available
            let modelManager = await ModelManager.shared
            if await modelManager.selectedModel == nil {
                if await modelManager.downloadedModels.isEmpty {
                    return "No speech model installed. Download one in Settings."
                } else {
                    return "Choose a speech model in Settings."
                }
            }
            return nil
            
        case .cloud:
            // Check if API key is configured
            guard let apiKey = KeychainService.shared.load(KeychainService.Key.apiKey),
                  !apiKey.isEmpty else {
                return "Add your API key in Settings."
            }
            return nil
        }
    }
}
