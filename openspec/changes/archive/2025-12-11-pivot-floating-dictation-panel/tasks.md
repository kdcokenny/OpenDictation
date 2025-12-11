# Tasks: Floating Dictation Panel Implementation

## Phase 1: Cleanup & Foundation ✓

### 1.1 Remove caret-following code
- [x] 1.1.1 Delete `Sources/OpenDictation/Views/DictationCaretPanel.swift`
- [x] 1.1.2 Delete `Sources/OpenDictation/Views/DictationCaretView.swift`
- [x] 1.1.3 Remove cursor position tracking from `CursorService.swift` (or delete if only used for caret)
- [x] 1.1.4 Remove CursorBounds package from `Package.swift` if no longer needed
- [x] 1.1.5 Remove any caret-related code from `AppDelegate.swift`

### 1.2 Update DictationOverlayPanel for new design
- [x] 1.2.1 Change positioning to fixed bottom-center (~60px from bottom)
- [x] 1.2.2 Update size to ~120×44px (capsule for 5 bars)
- [x] 1.2.3 Apply macOS glass material effect (`.regularMaterial` in SwiftUI)
- [x] 1.2.4 Verify `NSPanel` with `.nonactivatingPanel` behavior preserved
- [x] 1.2.5 Ensure `hidesOnDeactivate = false`

## Phase 2: Visual Components (partial)

### 2.1 Create WaveformView
- [x] 2.1.1 Create new file `Sources/OpenDictation/Views/WaveformView.swift`
- [x] 2.1.2 Implement 10 vertical bars in HStack (adjusted from 5 for pill design)
- [x] 2.1.3 Configure bar properties (2px width, 2px spacing, rounded corners)
- [x] 2.1.4 Wire WaveformView to real audio levels from RecordingService.audioLevel
- [x] 2.1.5 Implement height range (min 3px, max 16px for compact pill)
- [x] 2.1.6 Use primary label color (adapts to appearance)
- [x] 2.1.7 Smooth animation via TimelineView with real audio input

### 2.2 Create SineWaveAnimator
- [x] 2.2.1 Integrated into WaveformView via `isProcessing` parameter
- [x] 2.2.2 Implement sine wave pattern with phase offset per bar
- [x] 2.2.3 Continuous loop via TimelineView(.animation)
- [x] 2.2.4 Stop by switching isProcessing back to false

### 2.3 Update DictationHUDView
- [x] 2.3.1 Replace mic icon / bouncing dots with WaveformView
- [x] 2.3.2 Add state-driven switching: `recording` → organic motion, `processing` → sine wave
- [x] 2.3.3 Remove old `BouncingDotsView`

### 2.4 Panel Animations
- [x] 2.4.1 Implement appear animation (fade + scale, spring)
- [x] 2.4.2 Implement dismiss animation (fade + scale down, spring)
- [x] 2.4.3 Implement shake animation for error AND empty results (dampening pattern: ±5px→±2.5px→0, 0.3s)
- [x] 2.4.4 Implement result state icons (all primary color for consistency):
  - success: checkmark
  - copiedToClipboard: doc.on.clipboard
  - error: exclamationmark.triangle.fill (+ NSSound.beep())
  - empty: waveform.slash (silent)

## Phase 3: State Management ✓

### 3.1 Define state machine
- [x] 3.1.1 Define states: `idle`, `recording`, `processing`, `success`, `copiedToClipboard`, `error`, `empty`, `cancelled`
- [x] 3.1.2 Implement state transitions (hotkey, audio events, transcription result, escape)
- [x] 3.1.3 Make state observable by views (HUDVisualState enum for UI binding)

### 3.2 Fast-path optimization
- [x] 3.2.1 Track transcription start time
- [x] 3.2.2 If result returns in <0.5s, skip `processing` state (via `shouldSkipProcessingAnimation`)
- [x] 3.2.3 Go directly: `recording` → `success`/`error`/`empty`

### 3.3 Escape handling
- [x] 3.3.1 Implement Escape in `recording` state (cancel, discard, dismiss)
- [x] 3.3.2 Implement Escape in `processing` state (cancel/abort, dismiss)
- [x] 3.3.3 Wire up via global event monitor (`NSEvent.addGlobalMonitorForEvents`) since nonactivatingPanel doesn't receive key events

## Phase 4: Text Field Detection & Insertion ✓

### 4.1 Create TextFieldDetector
- [x] 4.1.1 Create new file `Sources/OpenDictation/Services/TextFieldDetector.swift`
- [x] 4.1.2 Implement `isInTextField() -> Bool` function
- [x] 4.1.3 Add AXRole check (AXTextField, AXTextArea, AXSearchField, AXComboBox, AXSecureTextField)
- [x] 4.1.4 Add AXSubrole check (AXSearchField, AXSecureTextField, AXTextInput)
- [x] 4.1.5 Add AXEditable check
- [x] 4.1.6 Add AXActions check (AXInsertText, AXDelete) via AXUIElementCopyActionNames
- [x] 4.1.7 Implement graceful fallback (if API fails, return false)

### 4.2 Update TextInsertionService
- [x] 4.2.1 Add method `insertOrCopy(_ text: String) -> InsertionResult`
- [x] 4.2.2 If `isInTextField()` → clipboard + paste
- [x] 4.2.3 Else → clipboard only (no paste, no clipboard restore)
- [x] 4.2.4 Return enum `InsertionResult` (.inserted, .copiedToClipboard)
- [x] 4.2.5 Wire up to AppDelegate via `onInsertText` callback

## Phase 5: Error Handling ✓

### 5.1 Empty result handling
- [x] 5.1.1 Detect empty/whitespace-only transcription (in `handleTranscriptionResult`)
- [x] 5.1.2 Trigger shake animation (HUDVisualState.empty triggers shake)
- [x] 5.1.3 Dismiss after shake completes (no sound) via `showEmptyAndDismiss()`

### 5.2 API error handling
- [x] 5.2.1 Catch transcription errors (`.transcriptionFailed` event)
- [x] 5.2.2 Show error state (primary-colored icon, no red tint)
- [x] 5.2.3 Play error sound (`NSSound.beep()`)
- [x] 5.2.4 Dismiss after 0.5s via `showErrorAndDismiss()`

### 5.3 Accessibility permission handling
- [x] 5.3.1 Check permissions on app launch (`PermissionsManager`)
- [x] 5.3.2 If denied during use, fallback to clipboard only (`TextFieldDetector` returns false on API failure)

## Phase 6: Audio Feedback ✓

### 6.1 Sound playback
- [x] 6.1.1 Create `AudioFeedbackService.swift`
- [x] 6.1.2 Bundle actual macOS dictation sounds from system (begin_record.caf, end_record.caf, dictation_error.caf)
- [x] 6.1.3 Play start sound on recording start (begin_record.caf)
- [x] 6.1.4 Play success sound on success/clipboard (end_record.caf)
- [x] 6.1.5 Play error sound on error (dictation_error.caf)

### 6.2 Volume ducking
- [x] 6.2.1 Use `AudioDeviceDuck` API (same as FaceTime/Siri) instead of muting
- [x] 6.2.2 Duck other audio by ~20dB during recording (0.1s ramp)
- [x] 6.2.3 Restore volume when recording ends (0.3s ramp)
- [x] 6.2.4 Duck first, then play start sound; play end sound while ducked, then restore
- [x] 6.2.5 Handle app quit during recording (restore in `applicationWillTerminate`)

## Phase 7: Hotkey Activation ✓

### 7.1 Implement toggle hotkey
- [x] 7.1.1 Default Option+Space via KeyboardShortcuts library
- [x] 7.1.2 Using KeyboardShortcuts (wraps Carbon APIs, user-customizable)
- [x] 7.1.3 First press → start recording, show panel
- [x] 7.1.4 Second press → stop recording, begin transcription

### 7.2 Ensure focus behavior
- [x] 7.2.1 Panel appears without stealing focus (NSPanel.nonactivatingPanel)
- [x] 7.2.2 After dismiss, focus remains on original app (already implemented)
- [x] 7.2.3 Paste goes to correct window (TextInsertionService handles this)

## Phase 8: Integration & Polish ✓

### 8.1 Wire everything together
- [x] 8.1.1 Connect hotkey → state machine → UI → transcription → insertion
- [x] 8.1.2 Test full flow: activate → speak → stop → paste

### 8.2 Edge case testing
- [x] 8.2.1 Cancel mid-recording (Escape)
- [x] 8.2.2 Cancel during processing (Escape)
- [x] 8.2.3 Empty transcription (silence)
- [x] 8.2.4 API error (network failure)
- [x] 8.2.5 Not in text field (verify clipboard only)
- [x] 8.2.6 Accessibility permission denied
- [x] 8.2.7 Fast transcription (<0.5s)
- [x] 8.2.8 Slow transcription (>10s)

### 8.3 Cleanup
- [x] 8.3.1 Remove any dead code from old design
- [x] 8.3.2 Update openspec docs to reflect new design
- [x] 8.3.3 Verify no regressions

## Phase 9: Settings UI ✓

### 9.1 Settings Window Infrastructure
- [x] 9.1.1 Create custom NSWindow for settings (SwiftUI Settings scene doesn't work with NSStatusItem menu bar apps)
- [x] 9.1.2 Host SwiftUI SettingsView in NSHostingController
- [x] 9.1.3 Wire up menu item to open settings window
- [x] 9.1.4 Reuse window on subsequent opens (don't recreate)

### 9.2 Settings View Components
- [x] 9.2.1 Create `SettingsView.swift` with native macOS grouped form style
- [x] 9.2.2 Add KeyboardShortcuts.Recorder for hotkey customization (top of settings)
- [x] 9.2.3 Add API Key field with show/hide toggle
- [x] 9.2.4 Add collapsible Advanced section (collapsed by default)
- [x] 9.2.5 Add Base URL field (default: https://api.openai.com/v1)
- [x] 9.2.6 Add Model field (default: whisper-1)
- [x] 9.2.7 Add Language picker with all 57 Whisper-supported languages
- [x] 9.2.8 Add Temperature slider (0.0 - 1.0)

### 9.3 Secure Storage
- [x] 9.3.1 Create `KeychainService.swift` for secure API key storage
- [x] 9.3.2 Store API key in macOS Keychain (not UserDefaults)
- [x] 9.3.3 Load API key on settings view appear
- [x] 9.3.4 Save API key on change

### 9.4 Language Data Model
- [x] 9.4.1 Create `WhisperLanguage.swift` with ISO 639-1 codes
- [x] 9.4.2 Include all 57 Whisper-supported languages
- [x] 9.4.3 Auto-detect option as first choice (empty code)

## Phase 10: Real Audio Waveform ✓

### 10.1 Wire WaveformView to RecordingService audio levels
- [x] 10.1.1 Pass `RecordingService.audioLevel` to WaveformView (via HUDState binding)
- [x] 10.1.2 Update WaveformView to use real audio level instead of sine wave during recording
- [x] 10.1.3 Keep sine wave animation for processing state (no audio input)
- [x] 10.1.4 Smooth/interpolate audio levels for natural bar movement
- [x] 10.1.5 Test with real microphone input

## Dependency Graph

```
Phase 1 (Cleanup)
    ↓
Phase 2 (Visual) ←──────────────┐
    ↓                           │
Phase 3 (State) ────────────────┤
    ↓                           │
Phase 4 (Detection/Insertion) ──┤
    ↓                           │
Phase 5 (Error Handling) ───────┤
    ↓                           │
Phase 6 (Audio) ────────────────┘
    ↓
Phase 7 (Hotkey)
    ↓
Phase 8 (Integration)
    ↓
Phase 9 (Settings UI) ✓
    ↓
Phase 10 (Real Audio Waveform) ✓
```

Phases 2-6 can largely be worked in parallel after Phase 1 is complete.
Phase 9 can be done in parallel with Phase 8.
Phase 10 requires Phase 8 (real RecordingService with audio metering).
