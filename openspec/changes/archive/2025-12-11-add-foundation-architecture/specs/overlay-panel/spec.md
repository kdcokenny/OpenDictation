# Overlay Panel Capability

## ADDED Requirements

### Requirement: Non-Activating Window

The overlay panel SHALL be an `NSPanel` subclass configured with `.nonactivatingPanel` style mask so it does not steal focus from the active application.

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

The overlay panel SHALL have `level` set to `.floating` so it appears above normal application windows.

#### Scenario: Panel visibility over other windows
- **WHEN** the overlay panel is shown
- **THEN** it appears above all normal application windows
- **AND** it appears below system alerts and menus

### Requirement: Transparent Background

The overlay panel SHALL have a transparent background (`backgroundColor = .clear`, `isOpaque = false`) to allow custom HUD styling.

#### Scenario: Panel appearance
- **WHEN** the overlay panel is displayed
- **THEN** only the SwiftUI content is visible
- **AND** there is no default window chrome or background

### Requirement: Available on All Spaces

The overlay panel SHALL have `collectionBehavior` including `.canJoinAllSpaces` so it appears regardless of which Space the user is on.

#### Scenario: User switches Spaces
- **WHEN** the overlay panel is visible
- **AND** the user switches to a different Space
- **THEN** the overlay panel remains visible on the new Space

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
