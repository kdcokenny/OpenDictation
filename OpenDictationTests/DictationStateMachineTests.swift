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
        
        sut.onShowPanel = { showPanelExpectation.fulfill() }
        sut.onStartRecording = { startRecordingExpectation.fulfill() }
        
        // When
        sut.send(.hotkeyPressed(context: .prose))
        
        // Then
        XCTAssertEqual(sut.state, .recording)
        XCTAssertEqual(sut.currentContext, .prose)
        waitForExpectations(timeout: 1)
    }
    
    func testRecordingToProcessingFlow() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        
        // When
        sut.send(.transcriptionStarted)
        
        // Then
        XCTAssertEqual(sut.state, .processing)
    }
    
    func testProcessingToSuccessFlow() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        sut.send(.transcriptionStarted)
        
        let hidePanelExpectation = expectation(description: "onHidePanel called")
        sut.onHidePanel = { hidePanelExpectation.fulfill() }
        
        // Mocking onInsertText to succeed
        sut.onInsertText = { _ in true }
        
        // When
        sut.send(.transcriptionCompleted(text: "Hello world"))
        
        // Then
        XCTAssertEqual(sut.state, .success)
        waitForExpectations(timeout: 1)
    }
    
    func testFastTranscriptionFlow() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        sut.onInsertText = { _ in true }
        
        // When - Transcription finishes BEFORE .transcriptionStarted is even sent
        sut.send(.transcriptionCompleted(text: "Hello fast"))
        
        // Then
        XCTAssertEqual(sut.state, .success)
    }
    
    // MARK: - Cancellation & ESC Flow
    
    func testCancelDuringRecording() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        let cancelExpectation = expectation(description: "onCancel called")
        sut.onCancel = { cancelExpectation.fulfill() }
        
        // When
        sut.send(.escapePressed)
        
        // Then
        XCTAssertEqual(sut.state, .cancelled)
        waitForExpectations(timeout: 1)
    }
    
    func testCancelDuringProcessing() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        sut.send(.transcriptionStarted)
        let cancelExpectation = expectation(description: "onCancel called")
        sut.onCancel = { cancelExpectation.fulfill() }
        
        // When
        sut.send(.escapePressed)
        
        // Then
        XCTAssertEqual(sut.state, .cancelled)
        waitForExpectations(timeout: 1)
    }
    
    // MARK: - Terminal to Idle
    
    func testTerminalStatesReturnToIdleAfterDismiss() {
        let terminalEvents: [DictationEvent] = [
            .transcriptionCompleted(text: "test"),
            .transcriptionFailed(error: "error"),
            .escapePressed
        ]
        
        for event in terminalEvents {
            sut = DictationStateMachine()
            sut.send(.hotkeyPressed(context: .prose))
            sut.onInsertText = { _ in true }
            sut.send(event)
            
            // Verify it's in a terminal state
            XCTAssertNotEqual(sut.state, .idle)
            
            // When
            sut.send(.dismissCompleted)
            
            // Then
            XCTAssertEqual(sut.state, .idle, "Failed to return to idle from terminal event: \(event)")
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
    }
    
    // MARK: - Error Handling
    
    func testTranscriptionFailure() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        
        // When
        sut.send(.transcriptionFailed(error: "Network error"))
        
        // Then
        XCTAssertEqual(sut.state, .error(message: "Network error"))
    }
    
    func testEmptyTranscription() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        
        // When
        sut.send(.transcriptionCompleted(text: "   "))
        
        // Then
        XCTAssertEqual(sut.state, .empty)
    }
    
    func testInsertionFailure() {
        // Given
        sut.send(.hotkeyPressed(context: .prose))
        
        // When
        sut.onInsertText = { _ in false } // Fail insertion
        sut.send(.transcriptionCompleted(text: "Important text"))
        
        // Then
        XCTAssertEqual(sut.state, .error(message: "Failed to insert text. Please try again."))
    }
}
