## ADDED Requirements

### Requirement: System Capability Detection
The system SHALL detect hardware capabilities to determine the optimal Whisper model for the device.

#### Scenario: Detect RAM size
- **WHEN** the app launches
- **THEN** the system detects available RAM via `ProcessInfo.physicalMemory`
- **AND** categorizes as: <8GB, 8GB, 16GB+

#### Scenario: Detect chip generation
- **WHEN** the app launches
- **THEN** the system detects the Apple Silicon chip generation (M1, M2, M3, M4)
- **AND** uses this for model recommendation

#### Scenario: Detect system language
- **WHEN** the app launches
- **THEN** the system detects the primary language from `Locale.current`
- **AND** determines if English-optimized models should be used

### Requirement: Automatic Model Recommendation
The system SHALL automatically recommend the best Whisper model based on detected system capabilities.

#### Scenario: Low RAM system
- **WHEN** the system has less than 8GB RAM
- **THEN** the recommended model is `ggml-tiny` (or `ggml-tiny.en` for English systems)

#### Scenario: 8GB RAM with older chip
- **WHEN** the system has 8GB RAM
- **AND** the chip is M1 or M2
- **THEN** the recommended model is `ggml-base` (or `ggml-base.en` for English systems)

#### Scenario: 8GB RAM with newer chip
- **WHEN** the system has 8GB RAM
- **AND** the chip is M3 or later
- **THEN** the recommended model is `ggml-large-v3-turbo-q5_0`

#### Scenario: High RAM system
- **WHEN** the system has 16GB or more RAM
- **THEN** the recommended model is `ggml-large-v3-turbo-q5_0`

### Requirement: Silent Foreground Model Upgrade (Wi-Fi Only)
The system SHALL automatically download the recommended model silently in the foreground when on Wi-Fi, without user interaction.

#### Scenario: First launch with Wi-Fi
- **WHEN** the app launches for the first time
- **AND** Wi-Fi is available (checked via `NWPathMonitor`)
- **AND** the recommended model is not the bundled model
- **THEN** the recommended model download starts silently in the foreground
- **AND** the user can dictate immediately with the bundled model

#### Scenario: First launch without Wi-Fi (offline or cellular only)
- **WHEN** the app launches for the first time
- **AND** Wi-Fi is not available
- **THEN** the bundled model is used
- **AND** the download is deferred until Wi-Fi becomes available on a future launch

#### Scenario: Subsequent launch with pending upgrade
- **WHEN** the app launches
- **AND** the recommended model is not downloaded
- **AND** Wi-Fi is available
- **THEN** the silent foreground download starts or resumes

#### Scenario: Download completes
- **WHEN** a silent foreground model download completes
- **AND** manual override is not set
- **THEN** the newly downloaded model becomes the selected model
- **AND** no notification or UI update occurs

#### Scenario: App quit during download
- **WHEN** a model download is in progress
- **AND** the user quits the app
- **THEN** the download pauses (not true background download in v1)
- **AND** download resumes on next Wi-Fi launch

### Requirement: Seamless Model Switching
The system SHALL switch to the upgraded model without interrupting user workflow.

#### Scenario: Model switch timing
- **WHEN** a better model download completes
- **AND** a dictation session is not in progress
- **THEN** the next dictation session uses the new model

#### Scenario: Model switch during dictation
- **WHEN** a better model download completes
- **AND** a dictation session is in progress
- **THEN** the current session continues with the existing model
- **AND** the next session uses the new model

### Requirement: Manual Model Override
The system SHALL allow power users to manually select a specific model, overriding automatic selection.

#### Scenario: Manual selection
- **WHEN** user selects a model in Advanced settings
- **THEN** manual override mode is enabled
- **AND** auto-recommendation is disabled
- **AND** the selected model is used regardless of system capabilities

#### Scenario: Reset to automatic
- **WHEN** user clicks "Reset to Automatic" in Advanced settings
- **THEN** manual override mode is disabled
- **AND** auto-recommendation is re-evaluated
- **AND** background download starts if needed

### Requirement: Advanced Model Management UI
The system SHALL provide an Advanced settings section for power users to manage models manually.

#### Scenario: View Advanced settings
- **WHEN** user opens the Advanced section in Settings
- **THEN** they see:
  - Current active model name and size
  - Auto-recommended model name (if different)
  - Dropdown to select any predefined model
  - Download button for undownloaded models
  - Delete button for downloaded models (except last model)
  - "Reset to Automatic" button

#### Scenario: Advanced section hidden by default
- **WHEN** user opens Settings
- **THEN** the Advanced section is collapsed or on a separate tab
- **AND** basic users see only mode toggle and language picker

### Requirement: Simplified Local Mode Settings
The system SHALL present a simplified settings UI for local transcription mode without quality tier selection.

#### Scenario: View main settings in Local mode
- **WHEN** user views Settings in Local mode
- **THEN** they see:
  - Mode toggle (On this Mac / Online)
  - Language picker
- **AND** no quality tier selection is shown
- **AND** the optimal model is auto-selected based on system capabilities

#### Scenario: Change language triggers model check (on Wi-Fi)
- **WHEN** user selects a different language
- **AND** Wi-Fi is available
- **THEN** the appropriate model variant is selected (`.en` vs multilingual)
- **AND** if the model isn't downloaded, silent foreground download starts
- **AND** no download prompt is shown to the user

#### Scenario: Change language while offline or on cellular
- **WHEN** user selects a different language
- **AND** Wi-Fi is not available
- **AND** the appropriate model for that language is not downloaded
- **THEN** the system continues using the current model
- **AND** download is deferred until Wi-Fi becomes available

## REMOVED Requirements

### Requirement: Quality Selection in Settings
**Reason**: Quality selection is now automatic based on system capabilities. Users no longer need to choose between Fast/Balanced/Best Quality tiers. The system detects hardware specs and selects the optimal model automatically.

**Migration**: 
- Read old `transcriptionQuality` value BEFORE removing it
- If user was on Fast tier → apply auto-recommendation
- If user was on Balanced/Best tier:
  - Check if corresponding model file actually exists via `FileManager.default.fileExists()`
  - If model exists on disk → enable manual override, keep their model
  - If model doesn't exist → apply auto-recommendation (user never completed the download)
- New users use auto-selection
