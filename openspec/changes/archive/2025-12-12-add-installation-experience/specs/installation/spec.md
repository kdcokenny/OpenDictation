# installation Specification

## Purpose

Provides a polished installation experience including styled DMG distribution and automatic detection of improper installation locations.

## ADDED Requirements

### Requirement: Styled DMG Distribution

The application SHALL be distributed as a styled DMG with visual guidance for installation.

#### Scenario: User opens DMG
- **WHEN** the user opens the DMG file
- **THEN** a Finder window appears with a custom background
- **AND** the app icon is displayed on the left side
- **AND** an arrow points toward the Applications folder alias on the right side
- **AND** the window is sized appropriately to show all elements

#### Scenario: DMG volume icon
- **WHEN** the DMG is mounted
- **THEN** the volume appears in Finder sidebar with a custom icon matching the app icon

### Requirement: Application Location Detection

The application SHALL detect when it is running from a temporary or improper location.

#### Scenario: Running from DMG
- **WHEN** the app is launched from a mounted DMG volume
- **THEN** the system detects it is running from a disk image

#### Scenario: Running from Downloads folder
- **WHEN** the app is launched from ~/Downloads/
- **THEN** the system detects it is running from a temporary location

#### Scenario: Running from Desktop folder
- **WHEN** the app is launched from ~/Desktop/
- **THEN** the system detects it is running from a temporary location

#### Scenario: Running from Documents folder
- **WHEN** the app is launched from ~/Documents/
- **THEN** the system detects it is running from a temporary location

#### Scenario: Running from Applications folder
- **WHEN** the app is launched from /Applications/ or ~/Applications/
- **THEN** the system detects it is properly installed
- **AND** no move prompt is shown

### Requirement: Move to Applications Prompt

The application SHALL offer to move itself to the Applications folder when running from an improper location.

#### Scenario: Offer to move
- **WHEN** the app detects it is running from a temporary location
- **THEN** a dialog appears asking "Move to Applications?"
- **AND** the dialog explains the benefits of proper installation
- **AND** the user can choose "Move to Applications" or "Don't Move"

#### Scenario: User accepts move
- **WHEN** the user clicks "Move to Applications"
- **THEN** the app is copied to /Applications/
- **AND** a success dialog appears offering to relaunch from the new location

#### Scenario: User declines move
- **WHEN** the user clicks "Don't Move"
- **THEN** the app continues running from the current location
- **AND** no further action is taken

### Requirement: Existing Application Replacement

The application SHALL handle the case where a previous version exists in Applications.

#### Scenario: Previous version exists
- **WHEN** the user accepts move to Applications
- **AND** a previous version of the app exists at the destination
- **THEN** a confirmation dialog asks if the user wants to replace the existing app
- **AND** if confirmed, the existing app is removed before copying

#### Scenario: Previous version is running
- **WHEN** the user accepts move to Applications
- **AND** a previous version of the app is currently running at the destination
- **THEN** the user is informed that the existing app must be quit first
- **AND** the move operation does not proceed until the existing app is quit

### Requirement: Relaunch from Applications

The application SHALL offer to relaunch from the Applications folder after a successful move.

#### Scenario: Relaunch after move
- **WHEN** the app has been successfully moved to Applications
- **AND** the user chooses to relaunch
- **THEN** the new copy in Applications is launched
- **AND** the current instance terminates
