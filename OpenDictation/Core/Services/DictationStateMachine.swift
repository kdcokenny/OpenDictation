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
    case hotkeyPressed(context: ContextProfile)
    case stopRecording(context: ContextProfile)
    case transcriptionStarted(sessionID: UUID)
    case transcriptionCompleted(sessionID: UUID, text: String)
    case transcriptionFailed(sessionID: UUID, error: String)
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
    
    private let logger = Logger.app(category: "StateMachine")
    
    // MARK: - Published State
    
    @Published private(set) var state: DictationState = .idle

    /// Identifies the current dictation so delayed work cannot affect a newer session.
    private(set) var activeSessionID: UUID?

    /// Prevents repeated key events from stopping the same recording more than once.
    private(set) var isStopRequested = false
    
    /// The context profile captured at hotkey press (persists across states)
    var currentContext: ContextProfile = .prose
    
    // MARK: - Mock Mode
    
    /// When true, state transitions occur without triggering service callbacks.
    /// Used for testing UI states without real recording/transcription.
    /// Auto-disables when state returns to `.idle`.
    var isMockMode: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when recording should start
    var onStartRecording: ((UUID) -> Void)?
    
    /// Called when recording should stop and transcription begin
    var onStopRecording: ((UUID) -> Void)?
    
    /// Called when the operation should be cancelled
    var onCancel: ((UUID) -> Void)?
    
    /// Called when the panel should be shown
    var onShowPanel: ((UUID) -> Void)?
    
    /// Called when the panel should be hidden
    var onHidePanel: (() -> Void)?
    
    /// Called when text should be delivered to the user.
    var onInsertText: ((String) -> TextDeliveryResult)?
    
    // MARK: - Event Handling
    
    /// Process an event and transition to the appropriate state.
    func send(_ event: DictationEvent) {
        let previousState = state
        
        switch (state, event) {
            
        // MARK: From Idle
        case (.idle, .hotkeyPressed(let context)):
            let sessionID = UUID()
            activeSessionID = sessionID
            isStopRequested = false
            currentContext = context
            state = .recording
            onShowPanel?(sessionID)
            if !isMockMode {
                onStartRecording?(sessionID)
            }
            
        // MARK: From Recording
        case (.recording, .hotkeyPressed(let context)):
            requestStop(context: context)
            
        case (.recording, .stopRecording(let context)):
            requestStop(context: context)
            
        case (.recording, .transcriptionStarted(let sessionID))
            where sessionID == activeSessionID:
            // Transcription has started, show processing state
            state = .processing
            
        case (.recording, .transcriptionCompleted(let sessionID, let text))
            where sessionID == activeSessionID:
            handleTranscriptionResult(.success(text))
            
        case (.recording, .transcriptionFailed(let sessionID, let error))
            where sessionID == activeSessionID:
            handleTranscriptionResult(.failure(error))
            
        case (.recording, .escapePressed):
            let sessionID = activeSessionID
            state = .cancelled
            if !isMockMode, let sessionID {
                onCancel?(sessionID)
            }
            onHidePanel?()
            
        // MARK: From Processing
        case (.processing, .transcriptionCompleted(let sessionID, let text))
            where sessionID == activeSessionID:
            handleTranscriptionResult(.success(text))
            
        case (.processing, .transcriptionFailed(let sessionID, let error))
            where sessionID == activeSessionID:
            handleTranscriptionResult(.failure(error))
            
        case (.processing, .escapePressed):
            let sessionID = activeSessionID
            state = .cancelled
            if !isMockMode, let sessionID {
                onCancel?(sessionID)
            }
            onHidePanel?()
            
        // MARK: From Terminal States
        case (.success, .dismissCompleted),
             (.copiedToClipboard, .dismissCompleted),
             (.error(_), .dismissCompleted),
             (.empty, .dismissCompleted),
             (.cancelled, .dismissCompleted):
            state = .idle
            activeSessionID = nil
            isStopRequested = false
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
            activeSessionID = nil
            isStopRequested = false
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

    private func requestStop(context: ContextProfile) {
        guard !isStopRequested, let sessionID = activeSessionID else { return }

        // Capture the context where dictation ended. App activation updates remain valid
        // until this point, then the transcription uses this final value.
        currentContext = context
        isStopRequested = true

        if !isMockMode {
            onStopRecording?(sessionID)
        }
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
                    let deliveryResult = onInsertText?(trimmed) ?? .failed("Text delivery unavailable.")
                    switch deliveryResult {
                    case .inserted:
                        state = .success
                    case .copiedOnly:
                        state = .copiedToClipboard
                    case .failed(let message):
                        state = .error(message: message)
                    }
                }
            }
            
        case .failure(let error):
            state = .error(message: error)
        }
        
        // Panel handles its own dismiss animation based on state
        onHidePanel?()
    }
}
