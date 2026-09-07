import XCTest
import Combine
@testable import OpenDictation

@MainActor
final class DictationStateMachineTests: XCTestCase {
    
    private var sut: DictationStateMachine!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        sut = DictationStateMachine()
        cancellables = []
    }
    
    override func tearDown() {
        sut = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func testInitialStateIsIdle() {
        XCTAssertEqual(sut.state, .idle)
    }
    
    // MARK: - Happy Path Transitions
    
    func testIdleToRecordingFlow() {
        // Given
        let showPanelExpectation = expectation(description: "onShowPanel called")
        let startRecordingExpectation = expectation(description: "onStartRecording called")
        
        sut.onShowPanel = { _ in showPanelExpectation.fulfill() }
        sut.onStartRecording = { _ in startRecordingExpectation.fulfill() }
        
        // When
        sut.send(.hotkeyPressed(context: .prose))
        
        // Then
        XCTAssertEqual(sut.state, .recording)
        XCTAssertEqual(sut.currentContext, .prose)
        waitForExpectations(timeout: 1)
    }
    
    func testRecordingToProcessingFlow() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        
        // When
        sut.send(.transcriptionStarted(sessionID: sessionID))
        
        // Then
        XCTAssertEqual(sut.state, .processing)
    }
    
    func testProcessingToSuccessFlow() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        sut.send(.transcriptionStarted(sessionID: sessionID))
        
        let hidePanelExpectation = expectation(description: "onHidePanel called")
        sut.onHidePanel = { hidePanelExpectation.fulfill() }
        
        // Mocking onInsertText to succeed
        sut.onInsertText = { _ in .inserted }
        
        // When
        sut.send(.transcriptionCompleted(sessionID: sessionID, text: "Hello world"))
        
        // Then
        XCTAssertEqual(sut.state, .success)
        waitForExpectations(timeout: 1)
    }
    
    func testFastTranscriptionFlow() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        sut.onInsertText = { _ in .inserted }
        
        // When - Transcription finishes BEFORE .transcriptionStarted is even sent
        sut.send(.transcriptionCompleted(sessionID: sessionID, text: "Hello fast"))
        
        // Then
        XCTAssertEqual(sut.state, .success)
    }
    
    // MARK: - Cancellation & ESC Flow
    
    func testCancelDuringRecording() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let cancelExpectation = expectation(description: "onCancel called")
        sut.onCancel = { _ in cancelExpectation.fulfill() }
        
        // When
        sut.send(.escapePressed)
        
        // Then
        XCTAssertEqual(sut.state, .cancelled)
        waitForExpectations(timeout: 1)
    }
    
    func testCancelDuringProcessing() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        sut.send(.transcriptionStarted(sessionID: sessionID))
        let cancelExpectation = expectation(description: "onCancel called")
        sut.onCancel = { _ in cancelExpectation.fulfill() }
        
        // When
        sut.send(.escapePressed)
        
        // Then
        XCTAssertEqual(sut.state, .cancelled)
        waitForExpectations(timeout: 1)
    }
    
    // MARK: - Terminal to Idle
    
    func testTerminalStatesReturnToIdleAfterDismiss() throws {
        for terminalState in ["success", "error", "cancelled"] {
            sut = DictationStateMachine()
            sut.send(.hotkeyPressed(context: .prose))
            let sessionID = try requireActiveSessionID()
            sut.onInsertText = { _ in .inserted }

            switch terminalState {
            case "success":
                sut.send(.transcriptionCompleted(sessionID: sessionID, text: "test"))
            case "error":
                sut.send(.transcriptionFailed(sessionID: sessionID, error: "error"))
            default:
                sut.send(.escapePressed)
            }
            
            // Verify it's in a terminal state
            XCTAssertNotEqual(sut.state, .idle)
            
            // When
            sut.send(.dismissCompleted)
            
            // Then
            XCTAssertEqual(sut.state, .idle, "Failed to return to idle from \(terminalState)")
            XCTAssertNil(sut.activeSessionID)
        }
    }
    
    // MARK: - Force Reset
    
    func testForceResetFromRecording() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        
        // When
        sut.send(.forceReset)
        
        // Then
        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.activeSessionID)
    }
    
    // MARK: - Error Handling
    
    func testTranscriptionFailure() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        
        // When
        sut.send(.transcriptionFailed(sessionID: sessionID, error: "Network error"))
        
        // Then
        XCTAssertEqual(sut.state, .error(message: "Network error"))
    }
    
    func testEmptyTranscription() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        
        // When
        sut.send(.transcriptionCompleted(sessionID: sessionID, text: "   "))
        
        // Then
        XCTAssertEqual(sut.state, .empty)
    }
    
    func testInsertionFailure() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        
        // When
        sut.onInsertText = { _ in .failed("Failed to insert text. Please try again.") }
        sut.send(.transcriptionCompleted(sessionID: sessionID, text: "Important text"))
        
        // Then
        XCTAssertEqual(sut.state, .error(message: "Failed to insert text. Please try again."))
    }

    func testCopiedOnlyDelivery() throws {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()

        // When
        sut.onInsertText = { _ in .copiedOnly }
        sut.send(.transcriptionCompleted(sessionID: sessionID, text: "Important text"))

        // Then
        XCTAssertEqual(sut.state, .copiedToClipboard)
    }

    func testStopCapturesFinalContextAndRunsOnlyOnce() throws {
        sut.send(.hotkeyPressed(context: .prose))
        let sessionID = try requireActiveSessionID()
        var stoppedSessionIDs: [UUID] = []
        sut.onStopRecording = { stoppedSessionIDs.append($0) }

        sut.send(.stopRecording(context: .code))
        sut.send(.stopRecording(context: .prose))

        XCTAssertEqual(stoppedSessionIDs, [sessionID])
        XCTAssertEqual(sut.currentContext, .code)
        XCTAssertTrue(sut.isStopRequested)
    }

    func testStaleTranscriptionEventsCannotAffectNewSession() throws {
        sut.send(.hotkeyPressed(context: .prose))
        let oldSessionID = try requireActiveSessionID()
        sut.send(.escapePressed)
        sut.send(.dismissCompleted)

        sut.send(.hotkeyPressed(context: .code))
        let newSessionID = try requireActiveSessionID()
        var insertedText: String?
        sut.onInsertText = {
            insertedText = $0
            return .inserted
        }

        sut.send(.transcriptionStarted(sessionID: oldSessionID))
        sut.send(.transcriptionCompleted(sessionID: oldSessionID, text: "stale"))

        XCTAssertEqual(sut.state, .recording)
        XCTAssertEqual(sut.activeSessionID, newSessionID)
        XCTAssertNil(insertedText)
    }

    func testCancellationRequestsPanelDismissal() {
        sut.send(.hotkeyPressed(context: .prose))
        var hideCount = 0
        sut.onHidePanel = { hideCount += 1 }

        sut.send(.escapePressed)

        XCTAssertEqual(sut.state, .cancelled)
        XCTAssertEqual(hideCount, 1)
    }

    private func requireActiveSessionID() throws -> UUID {
        try XCTUnwrap(sut.activeSessionID, "Expected an active dictation session")
    }
}
