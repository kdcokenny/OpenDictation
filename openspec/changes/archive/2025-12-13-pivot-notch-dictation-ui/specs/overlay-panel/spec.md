# Overlay Panel Spec Delta

## MODIFIED Requirements

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

### Requirement: Floating Window Level
The overlay panel SHALL have `level` set to `.statusBar + 8` so it appears above the menu bar and integrates with the notch area.

#### Scenario: Panel visibility over menu bar
- **WHEN** the overlay panel is shown
- **THEN** it appears above the menu bar
- **AND** it visually extends from the hardware notch

#### Scenario: Panel above other floating windows
- **WHEN** the overlay panel is shown
- **AND** other floating windows are present
- **THEN** the overlay panel appears above them

---

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

## ADDED Requirements

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

### Requirement: Global Escape Key Handling
The overlay panel SHALL use a global event monitor to intercept Escape key presses while visible, without becoming key window.

The escape key handling SHALL:
- Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` to intercept Escape
- Override `canBecomeKey` to return `false` to prevent focus stealing
- Take precedence over the active application when panel is visible (Escape does NOT bleed through)
- Dismiss the dictation UI immediately when Escape is pressed

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
