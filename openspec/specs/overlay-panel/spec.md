# overlay-panel Specification

## Purpose
TBD - created by archiving change add-foundation-architecture. Update Purpose after archive.
## Requirements
### Requirement: Non-Activating Window
The overlay panel SHALL be an `NSWindow` subclass (not `NSPanel`) configured with `.borderless` and `.fullSizeContentView` style masks so it does not steal focus from the active application.

#### Scenario: Panel shown while typing in another app
- **WHEN** the user is typing in TextEdit
- **AND** the overlay panel is shown
- **THEN** TextEdit remains the active application
- **AND** the text cursor remains in TextEdit
- **AND** keyboard input continues to go to TextEdit

#### Scenario: Panel clicked
- **WHEN** the user clicks on the overlay panel
- **THEN** the previously active application remains active
- **AND** keyboard focus is not transferred to the panel

---

### Requirement: Cannot Become Key Window

The overlay panel SHALL override `canBecomeKey` to return `false` to prevent it from ever becoming the key window.

#### Scenario: Attempt to make key
- **WHEN** the system or user attempts to make the panel the key window
- **THEN** the panel refuses to become key
- **AND** the current key window remains unchanged

### Requirement: Cannot Become Main Window

The overlay panel SHALL override `canBecomeMain` to return `false` to prevent it from ever becoming the main window.

#### Scenario: Attempt to make main
- **WHEN** the system attempts to make the panel the main window
- **THEN** the panel refuses to become main

### Requirement: Floating Window Level
The overlay panel SHALL have `level` set to `.screenSaver` so it reliably appears above all windows including fullscreen applications, even after hours of system use.

**Rationale:** The previous level `.statusBar + 8` (raw value 33) is too low in the macOS window hierarchy and can be deprioritized by the system after accumulated fullscreen transitions and Space switches over extended use. The `.screenSaver` level (raw value 1000) is the Apple-defined constant specifically designed for overlays that must appear over fullscreen apps. This is the production-standard pattern used by DynamicNotchKit, KeyboardCowboy, InputSourcePro, Loop, and other established overlay applications.

#### Scenario: Panel visibility over menu bar
- **WHEN** the overlay panel is shown
- **THEN** it appears above the menu bar
- **AND** it visually extends from the hardware notch

#### Scenario: Panel above fullscreen apps after extended use
- **WHEN** the overlay panel is shown
- **AND** the app has been running for several hours
- **AND** the user has frequently used fullscreen applications
- **AND** the user has switched between Spaces multiple times
- **THEN** the overlay panel appears reliably over fullscreen apps
- **AND** no app restart is required to maintain visibility

#### Scenario: Panel above other windows
- **WHEN** the overlay panel is shown
- **AND** other floating windows, pop-up menus, and overlays are present
- **THEN** the overlay panel appears above them

---

### Requirement: Window Key-Only-If-Needed Behavior

The overlay panel SHALL have `becomesKeyOnlyIfNeeded` set to `true` to prevent the system from demoting the window's priority while maintaining passive (non-activating) behavior.

**Rationale:** This property tells macOS: "This window CAN become key if absolutely necessary, but don't make it key otherwise." Combined with `canBecomeKey = false`, this creates a truly passive overlay that the system will not demote after accumulated system events. This is a critical defensive pattern used by production overlay apps (KeyboardCowboy, DockDoor) to maintain reliable visibility over extended use.

#### Scenario: Passive behavior maintained
- **WHEN** the overlay panel is visible
- **THEN** the panel does not steal focus from the active application
- **AND** keyboard input continues to the active application
- **AND** the text cursor remains in the active application

#### Scenario: System does not demote window
- **WHEN** the overlay panel is visible
- **AND** system events occur (fullscreen transitions, Space switches)
- **THEN** the system maintains the window's priority level
- **AND** the window continues to appear reliably over fullscreen apps

---

### Requirement: Transparent Background

The overlay panel SHALL have a transparent background (`backgroundColor = .clear`, `isOpaque = false`) to allow custom HUD styling.

#### Scenario: Panel appearance
- **WHEN** the overlay panel is displayed
- **THEN** only the SwiftUI content is visible
- **AND** there is no default window chrome or background

### Requirement: Available on All Spaces
The overlay panel SHALL have `collectionBehavior` including `.canJoinAllSpaces` and `.stationary` so it appears regardless of which Space the user is on.

#### Scenario: User switches Spaces
- **WHEN** the overlay panel is visible
- **AND** the user switches to a different Space
- **THEN** the overlay panel remains visible on the new Space

#### Scenario: Panel does not move with Space
- **WHEN** the overlay panel is visible
- **AND** the user initiates Space animation
- **THEN** the overlay panel stays fixed (stationary)

---

### Requirement: Works with Fullscreen Apps

The overlay panel SHALL have `collectionBehavior` including `.fullScreenAuxiliary` so it can appear over fullscreen applications.

#### Scenario: Fullscreen app active
- **WHEN** a fullscreen application is active
- **AND** the overlay panel is shown
- **THEN** the overlay panel appears over the fullscreen app

### Requirement: Does Not Hide on Deactivate

The overlay panel SHALL have `hidesOnDeactivate` set to `false` so it remains visible even when the app loses focus.

#### Scenario: App loses focus
- **WHEN** the overlay panel is visible
- **AND** the user activates another application
- **THEN** the overlay panel remains visible

### Requirement: Show at Position

The overlay panel SHALL provide a `show(at: CGPoint)` method that positions and displays the panel.

#### Scenario: Show panel at caret
- **WHEN** `show(at: CGPoint(x: 100, y: 200))` is called
- **THEN** the panel's origin is set to (100, 200)
- **AND** the panel becomes visible via `orderFrontRegardless()`

### Requirement: Hide Panel

The overlay panel SHALL provide a `hide()` method that removes the panel from screen.

#### Scenario: Hide panel
- **WHEN** `hide()` is called
- **THEN** the panel is removed from screen via `orderOut(nil)`

### Requirement: Notch-Aware Positioning
The overlay panel SHALL position itself based on the hardware notch location.

The positioning SHALL:
- Detect notch dimensions using `NSScreen.safeAreaInsets.top`
- Detect notch horizontal position using `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`
- Calculate expansion area to the left and right of the notch
- Apply a 100ms delay before rendering content after window creation

#### Scenario: Notch detection on MacBook with notch
- **WHEN** the application launches
- **AND** the built-in display has a notch
- **THEN** the panel detects the notch size and position
- **AND** positions the expanded content symmetrically around the notch

#### Scenario: Notch detection on non-notch display
- **WHEN** the application checks for notch
- **AND** `safeAreaInsets.top` is 0
- **THEN** the panel reports no notch present
- **AND** no visual panel is created

---

### Requirement: Render Delay
The overlay panel SHALL wait 100 milliseconds after window creation before rendering content to avoid rendering glitches.

#### Scenario: Initial render delay
- **WHEN** the panel window is created
- **THEN** the system waits 100ms before updating content
- **AND** content renders correctly without glitches

---

### Requirement: Window Collection Behavior
The overlay panel SHALL have specific collection behavior for proper system integration.

The collection behavior SHALL include:
- `.fullScreenAuxiliary` - Work with fullscreen apps
- `.stationary` - Don't move with Space switches  
- `.canJoinAllSpaces` - Appear on all Spaces
- `.ignoresCycle` - Don't appear in window cycling (Cmd+Tab)

#### Scenario: Fullscreen app active
- **WHEN** a fullscreen application is active
- **AND** the overlay panel is shown
- **THEN** the overlay panel appears over the fullscreen app

#### Scenario: Window cycling excludes panel
- **WHEN** the user presses Cmd+Tab
- **THEN** the overlay panel is not included in the window list

---

### Requirement: Singleton Event Monitor Architecture

Event monitoring (specifically Escape key detection) SHALL be handled by a singleton service that lives for the entire app lifetime, separate from the overlay panel lifecycle.

**Rationale:** Event monitors should not be embedded within `NotchOverlayPanel`, as this causes event monitors to be destroyed and recreated during screen configuration changes. When displays are connected/disconnected during active recording, a race condition between async dismissal animation and panel destruction causes the state machine to get stuck (never receiving `.dismissCompleted`), breaking Escape key handling and hotkey functionality. This follows NotchDrop's proven pattern of separating event monitoring from UI component lifecycle.

#### Scenario: Escape key works after display change during recording
- **GIVEN** the app is actively recording
- **WHEN** an external display is connected or disconnected
- **THEN** the recording session is gracefully cancelled
- **AND** the state machine returns to idle
- **AND** the Escape key continues to work for subsequent sessions
- **AND** the hotkey (Option+Space) continues to work for subsequent sessions
- **AND** no force-kill is required to recover

#### Scenario: Event monitor survives panel destruction
- **GIVEN** the singleton event monitor is active
- **WHEN** the overlay panel is destroyed during screen rebuild
- **THEN** the event monitor continues to function
- **AND** Escape key events are still detected globally

---

### Requirement: Synchronous Panel Cleanup

The overlay panel system SHALL provide a `destroy()` method for synchronous cleanup that ensures no async callbacks fire after the panel reference is cleared.

**Rationale:** The `hide()` method uses an async dismissal animation (0.5s delay) that can fire callbacks after the panel is already set to `nil` during screen rebuilds. This creates a race condition where the `onDismissCompleted` callback targets the wrong (new) panel, causing the state machine to never transition back to idle. The `destroy()` method performs immediate, synchronous cleanup suitable for screen change scenarios.

#### Scenario: Clean shutdown during screen change
- **WHEN** a screen configuration change is detected
- **AND** the overlay panel is currently visible
- **THEN** `destroy()` is called before setting the panel reference to nil
- **AND** no async callbacks fire after destroy() returns
- **AND** the window is closed immediately (no animation)
- **AND** all references are cleared synchronously

---

### Requirement: Global Escape Key Handling
Escape key presses SHALL be intercepted globally via a singleton event monitor service when the overlay panel is visible, without the panel ever becoming the key window.

The escape key handling SHALL:
- Use the singleton `EscapeKeyMonitor` service (lives for entire app lifetime)
- Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` to intercept Escape globally
- Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to consume Escape events
- Maintain `canBecomeKey = false` to prevent focus stealing
- Take precedence over the active application when panel is visible (Escape does NOT bleed through)
- Dismiss the dictation UI immediately when Escape is pressed
- Continue to work after panel destruction and recreation during screen changes

#### Scenario: Escape key takes precedence
- **WHEN** the user presses Escape
- **AND** the panel is visible
- **THEN** the dictation UI is dismissed
- **AND** the Escape key event is NOT passed to the active application
- **AND** the active application does not receive the Escape key

#### Scenario: No focus stealing
- **WHEN** the panel is visible
- **THEN** `canBecomeKey` returns `false`
- **AND** the user's active application retains keyboard focus
- **AND** typing continues in the active application

#### Scenario: Escape works after display change
- **WHEN** the panel is visible
- **AND** a display is connected or disconnected
- **THEN** the singleton event monitor continues to function
- **AND** Escape key presses are detected after panel rebuild
- **AND** the dictation UI can be dismissed with Escape

### Requirement: Screen Change Handling

The overlay panel system SHALL monitor for display configuration changes and recreate the panel when the notch screen changes.

The screen change handling SHALL:
- Observe `NSApplication.didChangeScreenParametersNotification`
- Use `displayUUID` (via `CGDisplayCreateUUIDFromDisplayID`) for stable screen identification
- Compare current notch screen UUID against the previous UUID to detect actual changes
- Skip rebuilding if the UUID is unchanged (prevents redundant work on minor parameter changes)
- When display changes interrupt active recording:
  - Cancel any in-progress transcription immediately
  - Stop recording if active
  - Restore system audio volume
  - Play error sound for user feedback
  - Send `.forceReset` event to state machine (resets from ANY state to idle)
- Destroy the existing panel using synchronous `destroy()` method
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
- **THEN** the active recording is cancelled with error sound feedback
- **AND** the transcription task is cancelled
- **AND** system audio volume is restored
- **AND** the state machine receives `.forceReset` event (transitioning to idle)
- **AND** then the panel is rebuilt (if notch screen available)
- **AND** the Escape key and Option+Space hotkey work immediately for next session

#### Scenario: Redundant notification filtered

- **WHEN** `didChangeScreenParametersNotification` fires
- **AND** the notch screen UUID is unchanged (e.g., resolution or refresh rate change)
- **THEN** no panel rebuild occurs
- **AND** the current session (if any) continues uninterrupted

