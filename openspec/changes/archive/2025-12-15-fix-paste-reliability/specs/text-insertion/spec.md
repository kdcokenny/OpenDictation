# Text Insertion Specification

## ADDED Requirements

### Requirement: Universal Paste Timing
The system SHALL use proper timing and event source configuration to ensure reliable paste operations.

#### Scenario: Clipboard stabilization before paste
- **WHEN** text is set to the clipboard for insertion
- **THEN** the system MUST wait at least 50ms before simulating the paste keystroke
- **AND** the system MUST verify the clipboard contains the expected text before pasting

#### Scenario: Paste completion before clipboard restoration
- **WHEN** the paste keystroke has been simulated
- **THEN** the system MUST wait at least 150ms synchronously before attempting to restore the clipboard
- **AND** the wait MUST be synchronous (not async dispatch) to guarantee ordering

#### Scenario: Event source configuration
- **WHEN** creating a CGEventSource for paste simulation
- **THEN** the system MUST use `.combinedSessionState` as the state ID
- **AND** the system MUST NOT use `.hidSystemState`

### Requirement: Input Interference Prevention
The system SHALL suppress local keyboard events during paste simulation to prevent user input from interfering.

#### Scenario: Keyboard suppression during paste
- **WHEN** the paste simulation begins
- **THEN** the system MUST configure the event source to suppress local keyboard events
- **AND** the system MUST permit local mouse events (user can still move cursor)
- **AND** the system MUST permit system-defined events (volume, brightness keys)

#### Scenario: User types during paste
- **WHEN** the user presses a key during paste simulation
- **THEN** the keypress MUST NOT interfere with the paste operation
- **AND** the paste MUST complete successfully

### Requirement: Explicit Command Key Events
The system SHALL post explicit Command key down/up events for maximum app compatibility.

#### Scenario: Four-event paste sequence
- **WHEN** simulating Cmd+V paste
- **THEN** the system MUST post events in this order: Command key down, V key down, V key up, Command key up
- **AND** V key events MUST have the Command flag set
- **AND** all events MUST be posted to `.cghidEventTap`

#### Scenario: App compatibility
- **WHEN** the target app does not recognize Command flag on V key alone
- **THEN** the explicit Command key events ensure the paste is recognized

### Requirement: Full Clipboard Preservation
The system SHALL preserve all clipboard content types during paste operations, not just plain text.

#### Scenario: Image in clipboard preserved
- **WHEN** the user has an image copied to the clipboard
- **AND** dictation completes and text is pasted
- **THEN** the original image data MUST be restored to the clipboard after the paste delay
- **AND** the image MUST be usable (pasteable into image editors)

#### Scenario: Multiple clipboard types preserved
- **WHEN** the clipboard contains multiple types (e.g., RTF, HTML, plain text)
- **AND** dictation completes and text is pasted
- **THEN** all original types and their data MUST be restored to the clipboard

#### Scenario: Empty clipboard handling
- **WHEN** the clipboard is empty before dictation
- **AND** dictation completes and text is pasted
- **THEN** the clipboard MUST be cleared after the paste delay (restored to empty state)

### Requirement: Paste Operation Serialization
The system SHALL prevent concurrent paste operations to avoid clipboard corruption.

#### Scenario: Concurrent paste rejection
- **WHEN** a paste operation is in progress
- **AND** another `insertText()` call is made
- **THEN** the second call MUST return immediately without pasting
- **AND** the second call MUST return `false` to indicate it was not processed
- **AND** the first paste operation MUST complete normally

#### Scenario: Lock release on all paths
- **WHEN** a paste operation starts
- **THEN** the operation lock MUST be released when the operation completes
- **AND** the lock MUST be released even if an error occurs
- **AND** the lock MUST be released even if the operation is cancelled

### Requirement: Clipboard Verification
The system SHALL verify clipboard content was set correctly before simulating paste.

#### Scenario: Successful clipboard set
- **WHEN** `setString` is called on the pasteboard
- **THEN** the system MUST read back the clipboard content
- **AND** the system MUST verify it matches the expected text
- **AND** only then proceed with paste simulation

#### Scenario: Failed clipboard set
- **WHEN** `setString` is called but verification fails
- **THEN** the system MUST NOT simulate the paste keystroke
- **AND** the system MUST log the failure
- **AND** the system MUST return `false`
