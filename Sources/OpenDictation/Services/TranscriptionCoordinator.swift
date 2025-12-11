import Foundation
import os.log

/// Coordinates transcription between local and cloud providers.
/// Selects the appropriate provider based on user settings.
final class TranscriptionCoordinator {
    
    // MARK: - Singleton
    
    static let shared = TranscriptionCoordinator()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.opendictation", category: "TranscriptionCoordinator")
    
    /// The local transcription provider
    private let localProvider = LocalTranscriptionProvider.shared
    
    /// The cloud transcription provider
    private let cloudProvider = CloudTranscriptionProvider.shared
    
    private init() {}
    
    // MARK: - Mode Access
    
    /// Returns the current transcription mode from UserDefaults.
    var currentMode: TranscriptionMode {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "transcriptionMode") ?? TranscriptionMode.local.rawValue
            return TranscriptionMode(rawValue: rawValue) ?? .local
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "transcriptionMode")
        }
    }
    
    /// Returns the appropriate provider for the current mode.
    var currentProvider: TranscriptionProvider {
        switch currentMode {
        case .local:
            return localProvider
        case .cloud:
            return cloudProvider
        }
    }
    
    // MARK: - Transcription
    
    /// Transcribes audio using the current mode's provider.
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: The transcribed text
    func transcribe(audioURL: URL) async throws -> String {
        let mode = currentMode
        logger.info("Transcribing with \(mode.rawValue) mode")
        
        switch mode {
        case .local:
            return try await localProvider.transcribe(audioURL: audioURL)
        case .cloud:
            return try await cloudProvider.transcribe(audioURL: audioURL)
        }
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
    
    /// Checks if local mode is available (has at least one model).
    func isLocalModeAvailable() async -> Bool {
        let modelManager = await ModelManager.shared
        return await !modelManager.downloadedModels.isEmpty
    }
    
    /// Checks if cloud mode is available (has API key).
    func isCloudModeAvailable() -> Bool {
        guard let apiKey = KeychainService.shared.load(KeychainService.Key.apiKey),
              !apiKey.isEmpty else {
            return false
        }
        return true
    }
}
