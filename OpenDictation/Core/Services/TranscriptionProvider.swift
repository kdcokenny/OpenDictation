import Foundation

/// Protocol for transcription backends.
/// Allows switching between local (whisper.cpp) and cloud (API) transcription.
protocol TranscriptionProvider {
    /// Transcribes the audio file at the given URL.
    /// - Parameters:
    ///   - audioURL: URL to the audio file (wav, m4a, mp3, etc.)
    ///   - context: The pre-captured context profile.
    /// - Returns: The transcribed text.
    func transcribe(audioURL: URL, context: ContextProfile) async throws -> String
}

/// Transcription mode selection.
enum TranscriptionMode: String, Codable, CaseIterable {
    case local
    case cloud
    
    var displayName: String {
        switch self {
        case .local: return "On This Mac"
        case .cloud: return "Online"
        }
    }
    
    var description: String {
        switch self {
        case .local: return "Transcribes on your Mac. Works without internet."
        case .cloud: return "Transcribes using a cloud service. Requires internet."
        }
    }
}
