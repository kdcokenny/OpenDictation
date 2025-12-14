# Change: Fix Notch UI and Escape Key Bugs

## Why

This change addresses two critical bugs:
1.  **Incorrect Notch UI Positioning**: The notch UI appears in the wrong location (bottom-middle of the main display) after a monitor is connected or disconnected. The previous implementation failed to correctly identify the new notch screen and calculate its position.
2.  **Escape Key Fails After Permission Prompt**: The escape key stops dismissing the dictation UI after the system's Accessibility permission prompt is shown. This is a major usability issue caused by the app's overlay panel losing focus.

## What Changes

### Notch Positioning Fix (via `NotchDrop` Pattern)
- **Adopt `NotchDrop`'s stateless rebuild strategy**, replacing the previous complex UUID-based comparison.
- Add `isBuiltin` and `builtin` properties to `NSScreen+Notch.swift` using `CGDisplayIsBuiltin` for robust screen identification.
- On any `didChangeScreenParametersNotification`, the app will now:
  - Completely destroy the existing notch UI panel.
  - Re-run the logic to find the correct built-in screen with a notch.
  - Create a new, correctly positioned UI panel if a notch screen is found.
- This ensures the UI always appears in the right place without complex state tracking.

### Escape Key Focus Fix
- After the blocking Accessibility permission prompt is shown, programmatically restore focus to the notch UI panel.
- This is done by calling `notchPanel.makeKeyAndOrderFront(nil)` immediately after the permission request in `AppDelegate`, ensuring the panel can receive key events again.

## Impact

- **Affected specs**: `overlay-panel` (logic revised for robustness)
- **Affected code**:
  - `OpenDictation/Views/Notch/NSScreen+Notch.swift` - Replaced `displayUUID` with `isBuiltin` logic.
  - `OpenDictation/App/AppDelegate.swift` - Overhauled screen handling logic and added focus restoration for escape key.
