## 1. Implementation: Notch Positioning Fix

- [x] 1.1 In `NSScreen+Notch.swift`, add the `isBuiltin` computed property.
- [x] 1.2 In `NSScreen+Notch.swift`, add the static `findScreenForNotch()` method.
- [x] 1.3 In `NSScreen+Notch.swift`, remove the old `displayUUID` property.
- [x] 1.4 In `AppDelegate.swift`, remove the `previousScreenUUID` property.
- [x] 1.5 In `AppDelegate.swift`, create a new `rebuildNotchUI()` method that destroys and recreates the panel using `NSScreen.findScreenForNotch()`.
- [x] 1.6 In `AppDelegate.swift`, update `applicationDidFinishLaunching` to:
  - Point the `didChangeScreenParametersNotification` observer to `@selector(rebuildNotchUI)`.
  - Remove the initial setup of services and instead call `rebuildNotchUI()` at the end to create the initial UI.
- [x] 1.7 In `AppDelegate.swift`, remove the old `handleScreenChange()` and `rebuildNotchPanel()` methods.

## 2. Implementation: Escape Key Fix

- [x] 2.1 In `AppDelegate.swift`, locate the `hotkeyService?.onHotkeyPressed` closure.
- [x] 2.2 Add the line `self?.notchPanel?.makeKey()` immediately after the `pm.requestAccessibilityIfNeeded()` call to restore focus.

## 3. Validation

- [x] 3.1 **Notch Fix**: Launch with built-in display, verify UI works.
- [x] 3.2 **Notch Fix**: Connect an external monitor, verify the UI remains correctly positioned on the notch display.
- [x] 3.3 **Notch Fix**: Disconnect the external monitor, verify the UI remains correct.
- [x] 3.4 **Notch Fix**: Trigger a screen change during a recording and verify the session is gracefully cancelled.
- [x] 3.5 **Escape Key Fix**: On a fresh install (or after resetting permissions), trigger the Accessibility prompt. After dismissing the prompt, press `esc` and verify it correctly cancels the UI.
- [x] 3.6 **Regression Test**: Verify the `esc` key still works as expected when no permission prompt is shown.

