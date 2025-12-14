## Context

The notch-based dictation UI is created once at app launch. The initial implementation for handling display changes was flawed, causing the UI to mis-position itself. Furthermore, a focus management bug prevented the escape key from working after the accessibility permission prompt was shown.

This revised design adopts a more robust, stateless pattern from `NotchDrop` for screen handling and adds a targeted fix for the focus issue.

## Goals / Non-Goals

**Goals:**
- UI automatically and **correctly** adapts to display configuration changes.
- **Fix the escape key failure** after permission prompts.
- Implement a simpler, more robust screen handling logic based on a proven application (`NotchDrop`).
- Safely handle active recording sessions during screen swaps by cancelling them.

**Non-Goals:**
- Graceful mid-recording state preservation during a screen swap (cancellation is the desired behavior).
- UI on non-notch external monitors.

## Decisions

### Decision: Adopt `NotchDrop`'s Stateless Rebuild-on-Change Pattern

Instead of tracking screen state with UUIDs, we will adopt a simpler, more robust pattern. On any `didChangeScreenParametersNotification`, we will unconditionally destroy the old UI and rebuild it from scratch.

**Rationale**: The previous UUID-based approach was an attempt to prevent unnecessary rebuilds but introduced complexity and failed to solve the core positioning problem. The `NotchDrop` application proves that a stateless "destroy and recreate" model is effective and reliable. It correctly handles all screen changes, including resolution, connection, and clamshell mode, by simply re-running the initial setup logic.

**Alternative considered**: The original UUID comparison was rejected as it was both complex and incorrect.

### Decision: Prioritize Built-in Display for Notch Detection

A new `NSScreen.findScreenForNotch()` method will be implemented. It will use `CGDisplayIsBuiltin` to identify the device's built-in display and check it for a notch first.

**Rationale**: This is the most reliable way to find the correct screen for the notch UI. Relying on screen order or other heuristics is fragile. This logic is borrowed directly from `NotchDrop`'s `findScreenFitsOurNeeds` and `isBuildinDisplay` methods.

### Decision: Restore Panel Focus After Permission Prompt

To fix the escape key bug, we will explicitly restore focus to the notch panel after the blocking accessibility permission prompt returns.

**Rationale**: The system permission prompt takes exclusive focus, causing our non-activating `NSPanel` to stop receiving key events. The standard AppKit solution is to make the panel the key window again after the prompt is dismissed. This is achieved by calling `notchPanel.makeKeyAndOrderFront(nil)` immediately after the synchronous `AXIsProcessTrustedWithOptions` call returns.

## Implementation Approach

```swift
// NSScreen+Notch.swift - New helper properties
var isBuiltin: Bool {
    let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
    guard let id = deviceDescription[screenNumberKey] as? NSNumber else { return false }
    return CGDisplayIsBuiltin(id.uint32Value) != 0
}

static func findScreenForNotch() -> NSScreen? {
    return NSScreen.screens.first { $0.isBuiltin && $0.hasNotch }
}

// AppDelegate.swift - New rebuild logic
@objc private func rebuildNotchUI() {
    // 1. Cancel any active session
    stateMachine?.send(.escapePressed)
    
    // 2. Destroy existing panel
    notchPanel?.hide()
    notchPanel = nil
    
    // 3. Find the correct screen and recreate
    if let screen = NSScreen.findScreenForNotch() {
        notchPanel = NotchOverlayPanel(screen: screen)
        wireNotchPanelCallbacks()
        logger.info("Notch UI rebuilt for screen.")
    } else {
        logger.info("No notch screen found. UI not shown.")
    }
}

// AppDelegate.swift - Escape key fix
hotkeyService?.onHotkeyPressed = { [weak self] in
    // ... existing logic ...
    if let pm = self.permissionsManager, !pm.isAccessibilityGranted {
        pm.requestAccessibilityIfNeeded()
        // Restore focus to the panel after the blocking prompt returns
        self?.notchPanel?.makeKeyAndOrderFront(nil)
    }
    // ... existing logic ...
}
```
