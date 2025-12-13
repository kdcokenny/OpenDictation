# Tasks: Notch-Based Dictation UI

## Phase 1: Foundation - Notch Detection & Window (Complete)

- [x] 1.1 Create `NSScreen+Notch.swift` extension with `notchSize` and `hasNotch` properties
- [x] 1.2 Create `NotchWindow.swift` - NSWindow subclass with NotchDrop's configuration
- [x] 1.3 Create `NotchViewModel.swift` - State management for panel states and animations
- [x] 1.4 Implement the critical 100ms render delay in window initialization

## Phase 2: UI Components - Initial Implementation (Complete)

- [x] 2.1 Create `NotchWaveformView.swift` - Initial waveform implementation
- [x] 2.2 Create `NotchDictationView.swift` - Initial main SwiftUI view
- [x] 2.3 Implement state-specific views (recording, processing, error, empty)

## Phase 3: Panel Integration (Complete)

- [x] 3.1 Create `NotchOverlayPanel.swift` - Replacement for `DictationOverlayPanel`
- [x] 3.2 Implement expand/collapse animations using `interactiveSpring`
- [x] 3.3 Wire up `NotchVisualState` to drive notch panel visual states
- [x] 3.4 Implement escape key handling for dismissal (global + local monitors)

## Phase 4: AppDelegate Integration (Complete)

- [x] 4.1 Add notch detection check in `setupServices()`
- [x] 4.2 Replace `DictationOverlayPanel` instantiation with `NotchOverlayPanel` for notch Macs
- [x] 4.3 Skip panel creation entirely for non-notch Macs (audio feedback only)
- [x] 4.4 Update state machine callbacks to use new panel methods

## Phase 5: Refinements - Match Reference Implementations (Complete)

### 5.1 Waveform Refinement (Boring Notch Style)
**Source**: `TheBoredTeam/boring.notch/boringNotch/components/Music/MusicVisualizer.swift`

- [x] 5.1.1 Change bar count from 5 to 4
- [x] 5.1.2 Use exact dimensions: `barWidth: 2`, `spacing: 2`, `totalHeight: 14`
- [x] 5.1.3 Replace sine wave with random independent bar heights (`0.35...1.0`)
- [x] 5.1.4 Implement audio-reactive behavior:
  - Idle (audioLevel < 0.15): Range `0.25...0.45`, update interval ~0.4s
  - Active (audioLevel >= 0.15): Range scaled by audioLevel, update interval ~0.2s
  - Smooth blend between modes using audioLevel as interpolation factor

### 5.2 NotchShape Implementation (Boring Notch Style)
**Source**: `TheBoredTeam/boring.notch/boringNotch/components/Notch/NotchShape.swift`

- [x] 5.2.1 Create `NotchShape.swift` with custom Path using quadCurves
- [x] 5.2.2 Use corner radii: `topCornerRadius: 6`, `bottomCornerRadius: 14`
- [x] 5.2.3 Make corner radii animatable via `animatableData`

### 5.3 Mask with "Ears" Effect (NotchDrop Style)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchView.swift` lines 82-127

- [x] 5.3.1 Add `leftEarMask` and `rightEarMask` computed properties to `NotchDictationView`
- [x] 5.3.2 Implement left "ear" overlay with `blendMode(.destinationOut)`
- [x] 5.3.3 Implement right "ear" overlay (mirrored)
- [x] 5.3.4 Apply overlays to content with `.compositingGroup()`
- [x] 5.3.5 Use spacing value: `16` (from NotchDrop)

### 5.4 View Alignment Fix (NotchDrop Style)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchView.swift` lines 42-67

- [x] 5.4.1 Change root view to `ZStack(alignment: .top)`
- [x] 5.4.2 Add `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)`
- [x] 5.4.3 Ensure content anchors to top of window (sticks to notch)

### 5.5 Processing State Fix

- [x] 5.5.1 Keep waveform visible on right side during processing state
- [x] 5.5.2 Show waveform with low idle activity (audioLevel: 0.05 for subtle breathing)
- [x] 5.5.3 Only change left icon to processing indicator

### 5.6 NSScreen Extension Fix
**Source**: `Lakr233/NotchDrop/NotchDrop/Ext+NSScreen.swift`

- [x] 5.6.1 Add guard: `guard leftPadding > 0, rightPadding > 0 else { return .zero }`

## Phase 6: Cleanup & Documentation (Complete)

- [x] 6.1 Mark `DictationOverlayPanel.swift` as deprecated (kept for reference)
- [x] 6.2 Mark `DictationHUDView.swift` as deprecated (kept for reference)
- [x] 6.3 Update README to document notch-only UI requirement
- [x] 6.4 Add note about filing issues for non-notch Mac UI support

## Phase 7: Testing & Validation (Complete)

- [x] 7.1 Test on notch MacBook - all states work correctly
- [x] 7.2 Test on non-notch Mac / external display - no UI appears, audio feedback works
- [x] 7.3 Test escape key dismissal in both recording and processing states
- [x] 7.4 Test fullscreen app compatibility
- [x] 7.5 Test Space switching behavior
- [x] 7.6 Verify notch UI "sticks" to hardware notch when moving windows
- [x] 7.7 Verify waveform looks jagged (not smooth wave) when speaking

## Dependencies

- Phase 1 must complete before Phase 2
- Phase 2 must complete before Phase 3
- Phase 3 must complete before Phase 4
- Phase 5 can start after Phase 4 (refinements to existing implementation)
- Phase 6 and 7 can run in parallel after Phase 5

## Files to Create/Modify in Phase 5

| File | Action | Source Reference |
|------|--------|------------------|
| `NotchWaveformView.swift` | **Rewrite** | Boring Notch `MusicVisualizer.swift` |
| `NotchShape.swift` | **Create** | Boring Notch `NotchShape.swift` |
| `NotchDictationView.swift` | **Major Edit** | NotchDrop `NotchView.swift` |
| `NSScreen+Notch.swift` | **Minor Edit** | NotchDrop `Ext+NSScreen.swift` |

## Key Values Reference

| Value | Source | Used In |
|-------|--------|---------|
| Bar count: 4 | Boring Notch `MusicVisualizer.swift` | `NotchWaveformView` |
| Bar width: 2px | Boring Notch `MusicVisualizer.swift` | `NotchWaveformView` |
| Bar spacing: 2px | Boring Notch `MusicVisualizer.swift` | `NotchWaveformView` |
| Bar height: 14px | Boring Notch `MusicVisualizer.swift` | `NotchWaveformView` |
| Top corner radius: 6 | Boring Notch `matters.swift` | `NotchShape` |
| Bottom corner radius: 14 | Boring Notch `matters.swift` | `NotchShape` |
| Spacing (ears): 16 | NotchDrop `NotchViewModel.swift` | `NotchDictationView` |
| Animation: interactiveSpring(0.5, 0.25, 0.125) | NotchDrop `NotchViewModel.swift` | `NotchViewModel` |
