## MODIFIED Requirements

### Requirement: Status Item Menu

The status item SHALL display a menu when clicked containing essential app controls.

#### Scenario: Click status item
- **WHEN** the user clicks the menu bar icon
- **THEN** a menu appears with at least:
  - "Check for Updates..." menu item
  - Separator
  - "Settings..." menu item
  - Separator
  - "Quit Open Dictation" menu item

## ADDED Requirements

### Requirement: Check for Updates Menu Item

The menu SHALL include a "Check for Updates..." item that triggers a manual update check.

#### Scenario: Check for updates
- **WHEN** the user clicks "Check for Updates..."
- **THEN** an immediate update check is performed via Sparkle
- **AND** if an update is available, Sparkle handles the download and installation
