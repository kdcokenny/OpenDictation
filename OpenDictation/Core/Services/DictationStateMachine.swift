import Foundation
import Combine
import os.log

/// All possible states of the dictation flow.
enum DictationState: Equatable {
    case idle
    case recording
    case processing
    case success
    case copiedToClipboard  // Text copied but not inserted (not in text field)
    case error(message: String)
    case empty
    case cancelled
}

/// Events that trigger state transitions.
enum DictationEvent {
    case hotkeyPressed
    case stopRecording
    case transcriptionStarted
    case transcriptionCompleted(text: String)
    case transcriptionFailed(error: String)
    case escapePressed
    case dismissCompleted
    case forceReset  // System-level interruption (display changes, sleep, etc.) - bypasses normal flow
}

/// Manages dictation state transitions with observable state for UI binding.
///
/// State transitions:
/// - `idle` → `recording` (hotkey)
/// - `recording` → `processing` (stop recording, if slow transcription)
/// - `recording` → `success`/`error`/`empty` (fast-path, <0.5s transcription)
/// - `recording` → `cancelled` (escape)
/// - `processing` → `success`/`error`/`empty` (transcription result)
/// - `processing` → `cancelled` (escape)
/// - `success`/`error`/`empty`/`cancelled` → `idle` (dismiss completed)
/// - `*` → `idle` (force reset - for system interruptions)
final class DictationStateMachine: ObservableObject {
    
    // MARK: - Logger
    
    private let logger = Logger(subsystem: "com.opendictation", category: "StateMachine")
    
    // MARK: - Published State
    
    @Published private(set) var state: DictationState = .idle
    
    // MARK: - Mock Mode
    
    /// When true, state transitions occur without triggering service callbacks.
    /// Used for testing UI states without real recording/transcription.
    /// Auto-disables when state returns to `.idle`.
    var isMockMode: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when recording should start
    var onStartRecording: (() -> Void)?
    
    /// Called when recording should stop and transcription begin
    var onStopRecording: (() -> Void)?
    
    /// Called when the operation should be cancelled
    var onCancel: (() -> Void)?
    
    /// Called when the panel should be shown
    var onShowPanel: (() -> Void)?
    
    /// Called when the panel should be hidden
    var onHidePanel: (() -> Void)?
    
    /// Called when text should be inserted. Returns true if inserted, false if clipboard-only.
    var onInsertText: ((String) -> Bool)?
    
    // MARK: - Event Handling
    
    /// Process an event and transition to the appropriate state.
    func send(_ event: DictationEvent) {
        let previousState = state
        
        switch (state, event) {
            
        // MARK: From Idle
        case (.idle, .hotkeyPressed):
            state = .recording
            onShowPanel?()
            if !isMockMode {
                onStartRecording?()
            }
            
        // MARK: From Recording
        case (.recording, .hotkeyPressed),
             (.recording, .stopRecording):
            if !isMockMode {
                onStopRecording?()
            }
            // Don't transition yet - wait for transcription result or timeout
            // The transition to .processing happens via transcriptionStarted event
            
        case (.recording, .transcriptionStarted):
            // Transcription has started, show processing state
            state = .processing
            
        case (.recording, .transcriptionCompleted(let text)):
            handleTranscriptionResult(.success(text))
            
        case (.recording, .transcriptionFailed(let error)):
            handleTranscriptionResult(.failure(error))
            
        case (.recording, .escapePressed):
            state = .cancelled
            if !isMockMode {
                onCancel?()
            }
            // Panel will dismiss via dismissCompleted event
            
        // MARK: From Processing
        case (.processing, .transcriptionCompleted(let text)):
            handleTranscriptionResult(.success(text))
            
        case (.processing, .transcriptionFailed(let error)):
            handleTranscriptionResult(.failure(error))
            
        case (.processing, .escapePressed):
            state = .cancelled
            if !isMockMode {
                onCancel?()
            }
            // Panel will dismiss via dismissCompleted event
            
        // MARK: From Terminal States
        case (.success, .dismissCompleted),
             (.copiedToClipboard, .dismissCompleted),
             (.error(_), .dismissCompleted),
             (.empty, .dismissCompleted),
             (.cancelled, .dismissCompleted):
            state = .idle
            // Auto-disable mock mode when returning to idle
            if isMockMode {
                isMockMode = false
                logger.debug("Mock mode auto-disabled")
            }
            
        // MARK: Force Reset (System Interruptions)
        case (_, .forceReset):
            // Emergency reset from ANY state (display changes, system sleep, etc.)
            // Bypasses normal state flow and callbacks
            state = .idle
            if isMockMode {
                isMockMode = false
                logger.debug("Mock mode auto-disabled via force reset")
            }
            logger.info("State machine force reset from \(String(describing: previousState))")
            
        // MARK: Invalid Transitions (Ignored)
        default:
            logger.debug("Ignored event \(String(describing: event)) in state \(String(describing: self.state))")
            return
        }
        
        if state != previousState {
            logger.debug("\(String(describing: previousState)) → \(String(describing: self.state))")
        }
    }
    
    // MARK: - Private Helpers
    
    private enum TranscriptionResult {
        case success(String)
        case failure(String)
    }
    
    private func handleTranscriptionResult(_ result: TranscriptionResult) {
        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                state = .empty
                // Empty result - shake animation, no text insertion
            } else {
                // In mock mode, skip text insertion and just go to success
                if isMockMode {
                    state = .success
                } else {
                    // Try to insert text, check if it was actually inserted or just clipboard
                    let wasInserted = onInsertText?(trimmed) ?? false
                    state = wasInserted ? .success : .copiedToClipboard
                }
            }
            
        case .failure(let error):
            state = .error(message: error)
        }
        
        // Panel handles its own dismiss animation based on state
        onHidePanel?()
    }
}
