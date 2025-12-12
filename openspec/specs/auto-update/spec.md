# auto-update Specification

## Purpose
TBD - created by archiving change add-auto-update. Update Purpose after archive.
## Requirements
### Requirement: Automatic Update Checks

The app SHALL automatically check for updates periodically in the background.

#### Scenario: Background check on launch
- **WHEN** the app is launched
- **AND** automatic update checks are enabled
- **THEN** Sparkle begins its update check schedule
- **AND** checks occur every 24 hours (86400 seconds)

#### Scenario: Update available
- **WHEN** a background check finds a newer version
- **AND** automatic updates are enabled
- **THEN** the update is downloaded silently in the background
- **AND** installed automatically when the app is idle or on next launch

### Requirement: Manual Update Check

The app SHALL allow users to manually trigger an update check.

#### Scenario: User triggers check
- **WHEN** the user clicks "Check for Updates..." in the menu
- **OR** clicks "Check Now" in Settings
- **THEN** an immediate update check is performed
- **AND** if an update is available, it is downloaded and installed

#### Scenario: No update available
- **WHEN** the user manually checks for updates
- **AND** no newer version exists
- **THEN** Sparkle displays "You're up to date" message

### Requirement: Update Signature Verification

All updates SHALL be cryptographically verified before installation.

#### Scenario: Valid signature
- **WHEN** an update is downloaded
- **AND** the EdDSA signature matches the public key in the app
- **THEN** the update is installed

#### Scenario: Invalid signature
- **WHEN** an update is downloaded
- **AND** the EdDSA signature does not match
- **THEN** the update is rejected
- **AND** installation does not proceed

### Requirement: Automatic Update Toggle

Users SHALL be able to enable or disable automatic update checks.

#### Scenario: Disable automatic checks
- **WHEN** the user disables "Automatically check for updates" in Settings
- **THEN** background update checks stop
- **AND** the preference persists across app restarts
- **AND** manual checks still work

#### Scenario: Enable automatic checks
- **WHEN** the user enables "Automatically check for updates" in Settings
- **THEN** background update checks resume on the normal schedule

### Requirement: Automatic Download Toggle

Users SHALL be able to control whether updates are downloaded automatically.

#### Scenario: Disable automatic downloads
- **WHEN** the user disables "Automatically download and install updates"
- **THEN** updates are not downloaded automatically
- **AND** the user must manually trigger updates

#### Scenario: Enable automatic downloads
- **WHEN** the user enables "Automatically download and install updates"
- **AND** automatic checks are enabled
- **THEN** updates are downloaded and installed silently

### Requirement: Version Display

The Settings view SHALL display the current app version.

#### Scenario: Version shown in Settings
- **WHEN** the user opens the Updates section in Settings
- **THEN** the current version is displayed (e.g., "Version 0.1.0-alpha (build 1)")

### Requirement: Appcast Feed

The app SHALL fetch update information from a hosted appcast.xml file.

#### Scenario: Appcast fetch
- **WHEN** an update check is triggered
- **THEN** the app fetches the appcast from the configured SUFeedURL
- **AND** parses available versions and download URLs

