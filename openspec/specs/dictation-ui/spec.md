# dictation-ui Specification

## Purpose
TBD - created by archiving change pivot-floating-dictation-panel. Update Purpose after archive.
## Requirements
### Requirement: Floating Dictation Panel
The system SHALL display a floating pill-shaped panel at the bottom-center of the screen during dictation.

The panel SHALL:
- Use macOS 26 Liquid Glass material (`NSGlassEffectView` with `.regular` style)
- Be positioned at bottom-center, ~60px from the bottom edge
- Have approximate dimensions of 120×44px with full capsule corner radius
- Float above all windows without stealing focus (`NSPanel` with `.nonactivatingPanel`)
- Remain visible across all Spaces and fullscreen apps

#### Scenario: Panel appears on dictation start
- **WHEN** the user activates dictation via hotkey
- **THEN** the panel appears at bottom-center with Liquid Glass material
- **AND** the panel does not steal focus from the active application

#### Scenario: Panel remains visible across spaces
- **WHEN** the panel is visible
- **AND** the user switches to another Space
- **THEN** the panel remains visible on the new Space

---

### Requirement: Waveform Visualization
The system SHALL display a 5-bar waveform visualization during recording that responds to audio input levels.

The waveform SHALL:
- Display 5 vertical bars with ~4px width and ~6px spacing
- Animate bar heights based on audio levels (8px minimum, 28px maximum)
- Use primary label color that adapts to light/dark appearance
- Have 2px corner radius on each bar
- Update smoothly with animation

#### Scenario: Waveform responds to audio
- **WHEN** the user is recording
- **AND** audio input is detected
- **THEN** the bar heights animate to reflect the audio levels

#### Scenario: Waveform shows silence state
- **WHEN** the user is recording
- **AND** no audio input is detected
- **THEN** all bars remain at minimum height (8px)

---

### Requirement: Processing Animation
The system SHALL display a sine wave animation during transcription processing.

The animation SHALL:
- Use the same 5 bars as the waveform
- Animate in a continuous sine wave pattern with phase offset per bar
- Only appear if processing takes longer than 0.5 seconds
- Continue until transcription completes or is cancelled

#### Scenario: Fast transcription skips processing animation
- **WHEN** transcription completes in less than 0.5 seconds
- **THEN** the processing animation is not shown
- **AND** the panel proceeds directly to success dismiss

#### Scenario: Slow transcription shows processing animation
- **WHEN** transcription takes longer than 0.5 seconds
- **THEN** the sine wave animation is displayed until completion

---

### Requirement: Panel Animations
The system SHALL animate the panel with native-feeling transitions.

#### Scenario: Panel appear animation
- **WHEN** dictation is activated
- **THEN** the panel fades in (0→1 opacity) and scales up (0.95→1.0)
- **AND** uses spring animation with duration 0.3s and bounce 0.15

#### Scenario: Panel dismiss on success
- **WHEN** transcription completes successfully
- **THEN** the panel fades out and scales down (1.0→0.95)
- **AND** uses spring animation with duration 0.2s and no bounce

#### Scenario: Panel dismiss on cancel
- **WHEN** the user cancels dictation (Escape key)
- **THEN** the panel dismisses with the same animation as success

#### Scenario: Panel shake on empty result
- **WHEN** transcription returns empty or whitespace-only text
- **THEN** the panel performs a horizontal shake animation (3 cycles, ±8px)
- **AND** then dismisses with fade out
- **AND** no sound is played

#### Scenario: Panel error state
- **WHEN** transcription fails with an error
- **THEN** the panel shows a red tint and error icon (exclamationmark.triangle)
- **AND** the error sound plays
- **AND** the panel dismisses after 0.5 seconds

---

### Requirement: Text Field Detection
The system SHALL detect whether the user is in a text input field before inserting text.

Detection SHALL check in order:
1. AXRole is one of: AXTextField, AXTextArea, AXSearchField, AXComboBox, AXSecureTextField
2. AXSubrole is one of: AXSearchField, AXSecureTextField, AXTextInput
3. AXEditable attribute is true
4. AXActions contains "AXInsertText" or "AXDelete"

If detection succeeds, the system SHALL use clipboard + paste insertion.
If detection fails or Accessibility API is unavailable, the system SHALL copy to clipboard only.

#### Scenario: In text field - auto paste
- **WHEN** transcription completes successfully
- **AND** the user is in a detected text field
- **THEN** the text is copied to clipboard and pasted automatically

#### Scenario: Not in text field - clipboard only
- **WHEN** transcription completes successfully
- **AND** the user is not in a detected text field
- **THEN** the text is copied to clipboard only
- **AND** no paste is performed

#### Scenario: Accessibility API failure - graceful fallback
- **WHEN** transcription completes successfully
- **AND** the Accessibility API fails (permission denied or error)
- **THEN** the text is copied to clipboard only
- **AND** no error is shown to the user

---

### Requirement: Toggle Hotkey Activation
The system SHALL support toggle-based activation via a global hotkey.

The hotkey SHALL:
- Default to Option+Space (hardcoded for v1)
- Work globally regardless of focused application
- First press starts recording and shows panel
- Second press stops recording and begins transcription
- Escape key cancels and dismisses at any time

#### Scenario: Start recording
- **WHEN** the user presses the hotkey
- **AND** dictation is not active
- **THEN** recording starts and the panel appears

#### Scenario: Stop recording
- **WHEN** the user presses the hotkey
- **AND** recording is in progress
- **THEN** recording stops and transcription begins

#### Scenario: Cancel with Escape
- **WHEN** the user presses Escape
- **AND** dictation is active (recording or processing)
- **THEN** dictation is cancelled
- **AND** audio is discarded
- **AND** the panel dismisses

---

### Requirement: Audio Feedback
The system SHALL provide audio feedback during dictation.

#### Scenario: Recording start sound
- **WHEN** recording starts successfully
- **THEN** the dictation start sound plays

#### Scenario: Success sound
- **WHEN** transcription completes and text is inserted/copied
- **THEN** the dictation end sound plays (after volume restore)

#### Scenario: Error sound
- **WHEN** transcription fails with an error
- **THEN** the dictation error sound plays

#### Scenario: Empty result - no sound
- **WHEN** transcription returns empty text
- **THEN** no sound is played

---

### Requirement: Volume Ducking
The system SHALL duck system volume during recording to prevent audio interference.

#### Scenario: Volume ducks on start
- **WHEN** recording starts
- **THEN** the system volume is saved and ducked to 0%

#### Scenario: Volume restores on end
- **WHEN** recording ends (any outcome)
- **THEN** the system volume is restored over ~0.3 seconds
- **AND** completion sounds play after volume restore

#### Scenario: Volume restored on app quit
- **WHEN** the application terminates during recording
- **THEN** the system volume is restored to the saved level

