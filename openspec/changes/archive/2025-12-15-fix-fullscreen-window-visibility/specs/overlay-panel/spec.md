# overlay-panel Spec Delta

## MODIFIED Requirements

### Requirement: Floating Window Level

The overlay panel SHALL have `level` set to `.screenSaver` so it reliably appears above all windows including fullscreen applications, even after hours of system use.

**Rationale:** The previous level `.statusBar + 8` (raw value 33) is too low in the macOS window hierarchy and can be deprioritized by the system after accumulated fullscreen transitions and Space switches over extended use. The `.screenSaver` level (raw value 1000) is the Apple-defined constant specifically designed for overlays that must appear over fullscreen apps. This is the production-standard pattern used by DynamicNotchKit, KeyboardCowboy, InputSourcePro, Loop, and other established overlay applications.

**Changed from:** `.statusBar + 8` (previous spec)
**Changed to:** `.screenSaver`

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

## ADDED Requirements

### Requirement: Window Key-Only-If-Needed Behavior

The overlay panel SHALL have `becomesKeyOnlyIfNeeded` set to `true` to prevent the system from demoting the window's priority while maintaining passive (non-activating) behavior.

**Rationale:** This property tells macOS: "This window CAN become key if absolutely necessary, but don't make it key otherwise." Combined with `canBecomeKey = false`, this creates a truly passive overlay that the system will not demote after accumulated system events. This is a critical defensive pattern used by production overlay apps (KeyboardCowboy, DockDoor) to maintain reliable visibility over extended use.

**Production pattern:** Used by KeyboardCowboy's `NotificationPanel` and DockDoor's `SharedPreviewWindowCoordinator`

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

## REMOVED Requirements

### Requirement: Utility Window Style Mask

**Removed:** The `.utilityWindow` style mask SHALL NOT be used in the overlay panel configuration.

**Rationale:** The `.utilityWindow` style mask is designed for tool palettes with smaller title bars, not for borderless passive overlays. It is not specified in any requirement, is not used by most production overlay apps (DynamicNotchKit, KeyboardCowboy, InputSourcePro, etc.), and is redundant when combined with `.borderless` and `.nonactivatingPanel`. Removing it simplifies the configuration and aligns with production patterns.

**Changed from:** `styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel, .utilityWindow]`
**Changed to:** `styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel]`

#### Scenario: Panel appearance unchanged
- **WHEN** the overlay panel is displayed
- **THEN** the appearance is identical to previous behavior
- **AND** no visual regressions occur (shadow, transparency, borders)

#### Scenario: Panel behavior unchanged
- **WHEN** the overlay panel is shown or hidden
- **THEN** the behavior is identical to previous implementation
- **AND** focus is never stolen from the active application

---

### Requirement: Singleton Event Monitor Architecture

Event monitoring (specifically Escape key detection) SHALL be handled by a singleton service that lives for the entire app lifetime, separate from the overlay panel lifecycle.

**Rationale:** The previous architecture embedded event monitors within `NotchOverlayPanel`, causing event monitors to be destroyed and recreated during screen configuration changes. When displays are connected/disconnected during active recording, a race condition between async dismissal animation and panel destruction caused the state machine to get stuck (never receiving `.dismissCompleted`), breaking Escape key handling and hotkey functionality. This follows NotchDrop's proven pattern of separating event monitoring from UI component lifecycle.

**Production pattern:** NotchDrop's `EventMonitors` singleton class

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

The overlay panel SHALL provide a `destroy()` method for synchronous cleanup that ensures no async callbacks fire after the panel reference is cleared.

**Rationale:** The previous `hide()` method used an async dismissal animation (0.5s delay) that could fire callbacks after the panel was already set to `nil` during screen rebuilds. This created a race condition where the `onDismissCompleted` callback would target the wrong (new) panel, causing the state machine to never transition back to idle. The `destroy()` method performs immediate, synchronous cleanup suitable for screen change scenarios.

**Production pattern:** NotchDrop's `WindowController.destroy()` method

#### Scenario: Clean shutdown during screen change
- **WHEN** a screen configuration change is detected
- **AND** the overlay panel is currently visible
- **THEN** `destroy()` is called before setting the panel reference to nil
- **AND** no async callbacks fire after destroy() returns
- **AND** the window is closed immediately (no animation)
- **AND** all references are cleared synchronously
