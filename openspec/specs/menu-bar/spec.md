# menu-bar Specification

## Purpose
TBD - created by archiving change add-foundation-architecture. Update Purpose after archive.
## Requirements
### Requirement: Status Item Presence

The app SHALL display a status item (icon) in the macOS menu bar when running.

#### Scenario: App launched
- **WHEN** the app is launched
- **THEN** a microphone icon appears in the menu bar
- **AND** the icon remains visible while the app is running

### Requirement: Agent App Mode

The app SHALL run as an agent (LSUIElement) so it does not appear in the Dock or Cmd+Tab switcher.

#### Scenario: App running
- **WHEN** the app is running
- **THEN** it does not appear in the Dock
- **AND** it does not appear in the Cmd+Tab application switcher
- **AND** it is only accessible via the menu bar icon

### Requirement: Status Item Menu

The status item SHALL display a menu when clicked containing essential app controls.

#### Scenario: Click status item
- **WHEN** the user clicks the menu bar icon
- **THEN** a menu appears with at least:
  - "Settings..." menu item
  - Separator
  - "Quit Open Dictate" menu item

### Requirement: Settings Menu Item

The menu SHALL include a "Settings..." item that opens the Settings window.

#### Scenario: Open settings
- **WHEN** the user clicks "Settings..."
- **THEN** the Settings window opens
- **AND** the Settings window becomes the key window

### Requirement: Quit Menu Item

The menu SHALL include a "Quit Open Dictate" item that terminates the application.

#### Scenario: Quit app
- **WHEN** the user clicks "Quit Open Dictate"
- **THEN** the application terminates gracefully

### Requirement: Keyboard Shortcut for Settings

The "Settings..." menu item SHALL have the standard keyboard shortcut Cmd+Comma.

#### Scenario: Settings shortcut
- **WHEN** the menu is open
- **AND** the user presses Cmd+,
- **THEN** the Settings window opens

### Requirement: Keyboard Shortcut for Quit

The "Quit Open Dictate" menu item SHALL have the standard keyboard shortcut Cmd+Q.

#### Scenario: Quit shortcut
- **WHEN** the menu is open
- **AND** the user presses Cmd+Q
- **THEN** the application terminates

