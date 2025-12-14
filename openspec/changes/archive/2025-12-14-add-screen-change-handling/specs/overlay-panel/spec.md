## ADDED Requirements

### Requirement: Screen Change Handling

The overlay panel system SHALL monitor for display configuration changes and recreate the panel when the notch screen changes.

The screen change handling SHALL:
- Observe `NSApplication.didChangeScreenParametersNotification`
- Use `displayUUID` (via `CGDisplayCreateUUIDFromDisplayID`) for stable screen identification
- Compare current notch screen UUID against the previous UUID to detect actual changes
- Skip rebuilding if the UUID is unchanged (prevents redundant work on minor parameter changes)
- Cancel any active recording or transcription session before rebuilding
- Destroy the existing panel before creating a new one
- Re-wire all panel callbacks after recreation
- Remove the observer when the application terminates

#### Scenario: External monitor connected

- **WHEN** the user connects an external monitor
- **AND** the built-in display (with notch) remains available
- **THEN** the panel continues to work on the built-in display
- **AND** no rebuild occurs if the notch screen UUID is unchanged

#### Scenario: External monitor disconnected

- **WHEN** the user disconnects an external monitor
- **AND** the built-in display (with notch) is the only remaining screen
- **THEN** the panel continues to work on the built-in display

#### Scenario: Clamshell mode entered

- **WHEN** the user closes the MacBook lid with an external monitor connected
- **AND** the system switches to the external display only
- **THEN** the panel is destroyed (no notch on external display)
- **AND** a log message indicates "No notch detected"
- **AND** audio feedback still works for dictation

#### Scenario: Clamshell mode exited

- **WHEN** the user opens the MacBook lid
- **AND** the built-in display (with notch) becomes available
- **THEN** a new panel is created on the notch display
- **AND** all callbacks are properly wired

#### Scenario: Screen change during active recording

- **WHEN** the display configuration changes
- **AND** the user is actively recording
- **THEN** the active recording is cancelled
- **AND** the transcription task is cancelled
- **AND** the state machine is reset
- **AND** then the panel is rebuilt (if notch screen available)

#### Scenario: Redundant notification filtered

- **WHEN** `didChangeScreenParametersNotification` fires
- **AND** the notch screen UUID is unchanged (e.g., resolution or refresh rate change)
- **THEN** no panel rebuild occurs
- **AND** the current session (if any) continues uninterrupted
