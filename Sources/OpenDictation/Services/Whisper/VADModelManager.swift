import Foundation
import os.log

/// Manages the bundled Voice Activity Detection (VAD) model.
/// The Silero VAD model is bundled in the app for automatic silence/noise filtering.
/// Adapted from VoiceInk/Whisper/VADModelManager.swift
final class VADModelManager {
    
    // MARK: - Singleton
    
    static let shared = VADModelManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.opendictation", category: "VADModelManager")
    
    /// Cached path to the VAD model
    private var cachedModelPath: String?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Returns the path to the bundled VAD model.
    /// The model is bundled in Resources/Models as ggml-silero-v5.1.2.bin
    func getModelPath() async -> String? {
        // Return cached path if available
        if let cached = cachedModelPath {
            return cached
        }
        
        // For SPM, use Bundle.module; for app bundle, use Bundle.main
        let possibleBundles = [Bundle.module, Bundle.main]
        
        for bundle in possibleBundles {
            // Try direct resource lookup
            if let modelURL = bundle.url(forResource: "ggml-silero-v5.1.2", withExtension: "bin") {
                cachedModelPath = modelURL.path
                logger.info("VAD model found in bundle: \(modelURL.path)")
                return modelURL.path
            }
            
            // Try Models subdirectory
            if let modelURL = bundle.url(forResource: "ggml-silero-v5.1.2", withExtension: "bin", subdirectory: "Models") {
                cachedModelPath = modelURL.path
                logger.info("VAD model found in bundle: \(modelURL.path)")
                return modelURL.path
            }
        }
        
        logger.warning("VAD model not found in bundle - VAD will be disabled")
        return nil
    }
}
