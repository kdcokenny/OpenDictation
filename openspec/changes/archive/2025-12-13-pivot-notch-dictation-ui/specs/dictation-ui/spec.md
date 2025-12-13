# Dictation UI Spec Delta

## REMOVED Requirements

### Requirement: Floating Dictation Panel
**Reason**: Replaced with notch-based UI that integrates with MacBook hardware notch.
**Migration**: Users with notch MacBooks get the new notch UI. Users without notch Macs have no visual UI (audio feedback only). Non-notch users who want visual UI can file a feature request.

---

## MODIFIED Requirements

### Requirement: Waveform Visualization
The system SHALL display a 5-bar waveform visualization during recording that responds to audio input levels.

The waveform SHALL:
- Display 5 vertical bars with ~2px width and ~2px spacing
- Animate bar heights based on audio levels (3px minimum, 16px maximum)
- Use white color on black background for notch integration
- Have rounded corners (half of bar width)
- Display a subtle "breathing" animation when user is silent (Siri-like idle state)
- Update smoothly with spring animation

#### Scenario: Waveform responds to audio
- **WHEN** the user is recording
- **AND** audio input is detected
- **THEN** the bar heights animate to reflect the audio levels
- **AND** the bars use the full height range (3px to 16px)

#### Scenario: Waveform shows idle breathing state
- **WHEN** the user is recording
- **AND** no audio input is detected (silence)
- **THEN** all bars display a subtle sine wave breathing animation
- **AND** the amplitude is small (approximately 0.12 of max)
- **AND** the breathing speed is slow (approximately 1.2 cycles per second)

---

### Requirement: Processing Animation
The system SHALL display a breathing circle animation during transcription processing.

The animation SHALL:
- Show a centered `circle.fill` SF Symbol
- Use `.symbolEffect(.breathe, options: .repeat(.continuous))` animation
- Display white icon on black background
- Only appear if processing takes longer than 0.5 seconds
- Continue until transcription completes or is cancelled

#### Scenario: Fast transcription skips processing animation
- **WHEN** transcription completes in less than 0.5 seconds
- **THEN** the processing animation is not shown
- **AND** the panel collapses directly

#### Scenario: Slow transcription shows processing animation
- **WHEN** transcription takes longer than 0.5 seconds
- **THEN** the breathing circle animation is displayed until completion

---

### Requirement: Panel Animations
The system SHALL animate the notch panel with native-feeling transitions.

#### Scenario: Panel expand animation
- **WHEN** dictation is activated
- **AND** the device has a hardware notch
- **THEN** the panel expands horizontally from the notch edges
- **AND** uses interactive spring animation (duration 0.5s, extraBounce 0.25)

#### Scenario: Panel collapse on success
- **WHEN** transcription completes successfully
- **THEN** the panel collapses back into the notch
- **AND** uses interactive spring animation

#### Scenario: Panel collapse on cancel
- **WHEN** the user cancels dictation (Escape key)
- **THEN** the panel collapses with the same animation as success

#### Scenario: Panel shake on empty result
- **WHEN** transcription returns empty or whitespace-only text
- **THEN** the icon (not the notch panel) performs a horizontal shake animation (3 cycles, ±8px)
- **AND** then the panel collapses into the notch
- **AND** no sound is played

#### Scenario: Panel error state
- **WHEN** transcription fails with an error
- **THEN** the panel shows `xmark.circle.fill` icon in white
- **AND** the error sound plays
- **AND** the panel collapses after brief display

---

## ADDED Requirements

### Requirement: Notch-Based Panel
The system SHALL display a Dynamic Island-style dictation panel that expands from the MacBook hardware notch.

The panel SHALL:
- Detect the hardware notch location using `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`
- Expand horizontally (left and right) from the notch edges during recording
- Stay at the notch's vertical height (no dropdown)
- Use solid black background matching the hardware notch color
- Display white icons and waveform elements
- Float above all windows including fullscreen apps

#### Scenario: Panel appears on notch MacBook
- **WHEN** the user activates dictation via hotkey
- **AND** the device has a hardware notch
- **THEN** the panel expands horizontally from the notch edges
- **AND** does not steal focus from the active application

#### Scenario: No panel on non-notch Mac
- **WHEN** the user activates dictation via hotkey
- **AND** the device does not have a hardware notch
- **THEN** no visual panel is displayed
- **AND** audio feedback (start/end sounds) still plays
- **AND** transcription still works normally

---

### Requirement: Recording State Display
The system SHALL display a dual-element layout during recording.

The layout SHALL:
- Show `record.circle.fill` SF Symbol on the left side with `.pulse.byLayer` animation
- Show 5-bar waveform visualization on the right side
- Position elements symmetrically around the hardware notch center
- Use white color for all visual elements

#### Scenario: Recording state layout
- **WHEN** recording is active
- **THEN** the left side shows a pulsing record icon
- **AND** the right side shows the waveform visualization
- **AND** both elements are white on black background

---

### Requirement: Non-Notch Mac Behavior
The system SHALL gracefully handle devices without a hardware notch.

#### Scenario: Non-notch Mac dictation
- **WHEN** the user has a non-notch MacBook or external display
- **AND** activates dictation via hotkey
- **THEN** recording and transcription work normally
- **AND** audio feedback sounds play at appropriate times
- **AND** no visual UI is displayed
- **AND** text is inserted or copied to clipboard as normal

#### Scenario: Feature request guidance
- **WHEN** a non-notch Mac user wants visual UI
- **THEN** documentation directs them to file a GitHub issue to request the feature
