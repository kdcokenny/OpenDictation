import Foundation

/// Errors that can occur during local Whisper transcription.
/// Adapted from VoiceInk/Whisper/WhisperError.swift
enum WhisperError: Error, Identifiable, LocalizedError {
    case modelNotFound
    case modelLoadFailed
    case transcriptionFailed
    case audioLoadFailed
    case vadModelNotFound
    case cancelled
    
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
        case .vadModelNotFound:
            return "Voice detection model missing."
        case .cancelled:
            return "Transcription was canceled."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelNotFound:
            return "Download a speech model in Settings."
        case .modelLoadFailed:
            return "Try a different model, or download this one again."
        case .transcriptionFailed:
            return "Try again. If this keeps happening, try a different model."
        case .audioLoadFailed:
            return "The audio file might be damaged or in an unsupported format."
        case .vadModelNotFound:
            return "Reinstall Open Dictation to fix this."
        case .cancelled:
            return nil
        }
    }
}
