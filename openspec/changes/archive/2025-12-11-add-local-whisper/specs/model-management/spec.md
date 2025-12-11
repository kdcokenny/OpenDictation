# Model Management

Download, storage, and selection of Whisper models for local transcription.

## ADDED Requirements

### Requirement: Bundled Default Model
The system SHALL bundle a default Whisper model in the app for instant first-run experience.

#### Scenario: First launch instant use
- **WHEN** the app launches for the first time
- **THEN** the bundled `ggml-tiny.en` model is copied to Application Support
- **AND** dictation works immediately without any download

#### Scenario: Bundled model already copied
- **WHEN** the app launches and the bundled model already exists in Application Support
- **THEN** no copy operation occurs

### Requirement: Deletable Bundled Model
The system SHALL allow users to delete the bundled model to free disk space or replace with preferred model.

#### Scenario: Delete bundled model
- **WHEN** the user deletes the bundled model from Settings
- **AND** another model is available or Cloud mode is selected
- **THEN** the bundled model is removed from Application Support
- **AND** the user is not forced to re-download it

#### Scenario: Delete last local model
- **WHEN** the user attempts to delete their only local model
- **AND** Cloud mode is not configured
- **THEN** a warning is shown that Local mode will be unavailable
- **AND** user can confirm or cancel deletion

### Requirement: Model Storage Location
The system SHALL store downloaded models in the Application Support directory.

#### Scenario: Model file location
- **WHEN** a model is downloaded or copied from bundle
- **THEN** it is saved to `~/Library/Application Support/com.opendictation/Models/`
- **AND** the directory is created if it does not exist

### Requirement: Model Download
The system SHALL allow users to download additional models from Hugging Face.

#### Scenario: Download additional model
- **WHEN** user selects an undownloaded model in Settings
- **AND** clicks download
- **THEN** the model downloads from Hugging Face
- **AND** progress is shown during download

#### Scenario: Download completes
- **WHEN** a model download finishes
- **THEN** the model is saved to Application Support
- **AND** becomes available for selection

#### Scenario: Download failure
- **WHEN** a model download fails due to network error
- **THEN** an error message is displayed
- **AND** user can retry

### Requirement: Quality Selection in Settings
The system SHALL allow users to select transcription quality using Apple-style tiers.

#### Scenario: View quality options
- **WHEN** user views quality selection in Settings (Local mode)
- **THEN** they see three quality tiers:
  - Fast (included with app)
  - Balanced
  - Best Quality
- **AND** each tier shows a brief description
- **AND** no technical model names are visible

#### Scenario: Switch quality tier
- **WHEN** user selects a different quality tier
- **THEN** the appropriate model is selected based on quality + language
- **AND** if the model isn't downloaded, a download prompt appears
- **AND** selection persists across app restarts

### Requirement: Language Selection
The system SHALL allow users to select their dictation language separately from quality.

#### Scenario: Language affects model selection
- **WHEN** user selects English as language
- **THEN** English-optimized (.en) models are used
- **WHEN** user selects any other language
- **THEN** multilingual models are used silently
- **AND** user never sees "multilingual" as a concept

### Requirement: Model Deletion
The system SHALL allow users to delete downloaded models to free disk space.

#### Scenario: Delete non-active model
- **WHEN** user deletes a model that is not currently active
- **THEN** the model file is removed from disk
- **AND** the model shows as "not downloaded" in the list

#### Scenario: Delete active model
- **WHEN** user deletes the currently active model
- **THEN** the model file is removed
- **AND** user is prompted to select another model or switch to Cloud mode

### Requirement: Predefined Model List
The system SHALL provide a curated list of recommended Whisper models.

#### Scenario: Model list contents
- **WHEN** user views model selection
- **THEN** they see at minimum:
  - `ggml-tiny.en` (75 MB) - Bundled, fastest
  - `ggml-base.en` (142 MB) - Better quality
  - `ggml-large-v3-turbo-q5_0` (547 MB) - Best accuracy

### Requirement: Model Loading
The system SHALL load the selected model into memory for transcription.

#### Scenario: Model load on transcription
- **WHEN** transcription is requested
- **AND** the selected model is not loaded
- **THEN** the model is loaded from disk
- **AND** transcription proceeds after loading

#### Scenario: Model already loaded
- **WHEN** transcription is requested
- **AND** the selected model is already loaded
- **THEN** transcription proceeds immediately without reloading

### Requirement: Advanced Settings
The system SHALL provide advanced transcription settings in a collapsible section for power users.

#### Scenario: Advanced section collapsed by default
- **WHEN** user opens Settings
- **THEN** Advanced section is collapsed
- **AND** basic settings are visible

#### Scenario: Advanced settings available
- **WHEN** user expands Advanced section
- **THEN** they can configure:
  - Temperature (0-1 slider)
  - Initial prompt (text field)
  - Translate to English (toggle, when multilingual model)
