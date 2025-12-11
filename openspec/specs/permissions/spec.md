# permissions Specification

## Purpose
TBD - created by archiving change add-foundation-architecture. Update Purpose after archive.
## Requirements
### Requirement: Accessibility Permission Check

The system SHALL check whether Accessibility permission has been granted using `AXIsProcessTrusted()`.

#### Scenario: Permission already granted
- **WHEN** the app launches and Accessibility permission was previously granted
- **THEN** `isAccessibilityGranted` returns `true`
- **AND** no system prompt is shown

#### Scenario: Permission not granted
- **WHEN** the app launches and Accessibility permission has not been granted
- **THEN** `isAccessibilityGranted` returns `false`

### Requirement: Accessibility Permission Request

The system SHALL request Accessibility permission by calling `AXIsProcessTrustedWithOptions()` with the prompt option set to `true`.

#### Scenario: User grants permission
- **WHEN** the permission request is triggered
- **THEN** macOS displays the Accessibility permission dialog
- **AND** if the user grants permission, `isAccessibilityGranted` updates to `true`

#### Scenario: User denies permission
- **WHEN** the permission request is triggered
- **AND** the user does not grant permission
- **THEN** `isAccessibilityGranted` remains `false`

### Requirement: Microphone Permission Check

The system SHALL check whether Microphone permission has been granted using `AVCaptureDevice.authorizationStatus(for: .audio)`.

#### Scenario: Permission already granted
- **WHEN** the app checks microphone permission
- **AND** permission was previously granted
- **THEN** `isMicrophoneGranted` returns `true`

#### Scenario: Permission not determined
- **WHEN** the app checks microphone permission
- **AND** the user has never been prompted
- **THEN** `isMicrophoneGranted` returns `false`

### Requirement: Microphone Permission Request

The system SHALL request Microphone permission by calling `AVCaptureDevice.requestAccess(for: .audio)`.

#### Scenario: User grants permission
- **WHEN** the permission request is triggered
- **THEN** macOS displays the Microphone permission dialog
- **AND** if the user grants permission, `isMicrophoneGranted` updates to `true`

### Requirement: Combined Permission Status

The system SHALL expose an `allPermissionsGranted` property that returns `true` only when both Accessibility and Microphone permissions are granted.

#### Scenario: All permissions granted
- **WHEN** both `isAccessibilityGranted` and `isMicrophoneGranted` are `true`
- **THEN** `allPermissionsGranted` returns `true`

#### Scenario: Missing permission
- **WHEN** either `isAccessibilityGranted` or `isMicrophoneGranted` is `false`
- **THEN** `allPermissionsGranted` returns `false`

