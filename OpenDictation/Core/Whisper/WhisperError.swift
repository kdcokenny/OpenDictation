import Foundation

/// Errors that can occur during local Whisper transcription.
enum WhisperError: Error, Identifiable, LocalizedError {
    case modelNotFound
    case modelLoadFailed
    case transcriptionFailed
    case audioLoadFailed
    
    var id: String { String(describing: self) }
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Speech model not found."
        case .modelLoadFailed:
            return "Couldn't load the speech model."
        case .transcriptionFailed:
            return "Couldn't transcribe the recording."
        case .audioLoadFailed:
            return "Couldn't load the audio file."
        }
    }
}
