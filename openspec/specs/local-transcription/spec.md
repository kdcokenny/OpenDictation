# local-transcription Specification

## Purpose
TBD - created by archiving change add-local-whisper. Update Purpose after archive.
## Requirements
### Requirement: Transcription Mode Toggle
The system SHALL support switching between Local and Cloud transcription modes via Settings.

#### Scenario: Local mode selected
- **WHEN** user selects Local mode in Settings
- **THEN** transcription uses the local whisper.cpp model
- **AND** no network connection is required

#### Scenario: Cloud mode selected
- **WHEN** user selects Cloud mode in Settings
- **AND** API key is configured
- **THEN** transcription uses the cloud API endpoint

#### Scenario: Default mode on first launch
- **WHEN** the app launches for the first time
- **THEN** Local mode is selected by default
- **AND** the bundled model is ready for use

### Requirement: Local Transcription
The system SHALL transcribe audio locally using whisper.cpp when Local mode is selected.

#### Scenario: Successful local transcription
- **WHEN** recording stops in Local mode
- **AND** a local model is available
- **THEN** the audio is transcribed using whisper.cpp
- **AND** the transcribed text is returned

#### Scenario: No local model available
- **WHEN** recording stops in Local mode
- **AND** no local model exists
- **THEN** an error is displayed prompting model download

### Requirement: Voice Activity Detection
The system SHALL use Voice Activity Detection (VAD) to filter silence and background noise during transcription.

#### Scenario: VAD filters silence
- **WHEN** audio contains periods of silence
- **THEN** VAD identifies non-speech segments
- **AND** whisper.cpp skips processing those segments
- **AND** transcription is faster with fewer hallucinations

### Requirement: Output Filtering
The system SHALL automatically filter transcription output to remove artifacts and filler words.

#### Scenario: Hallucination markers removed
- **WHEN** transcription contains `[BLANK_AUDIO]`, `[MUSIC]`, or similar markers
- **THEN** these markers are removed from the final text

#### Scenario: Filler words removed
- **WHEN** transcription contains filler words (uh, um, uhm, ah, eh, hmm)
- **THEN** these filler words are removed from the final text

#### Scenario: Whitespace normalized
- **WHEN** transcription contains excessive whitespace
- **THEN** multiple spaces are collapsed to single spaces
- **AND** leading/trailing whitespace is trimmed

### Requirement: Whisper Context Management
The system SHALL manage whisper.cpp contexts as thread-safe actors to prevent concurrent access issues.

#### Scenario: Sequential transcriptions
- **WHEN** multiple transcription requests arrive
- **THEN** they are processed sequentially through the actor
- **AND** no concurrent access to whisper.cpp occurs

#### Scenario: Context cleanup
- **WHEN** a transcription completes or is cancelled
- **THEN** the whisper context resources are properly released

### Requirement: Audio Format Handling
The system SHALL convert recorded audio to the format required by whisper.cpp (16-bit PCM, 16kHz, mono).

#### Scenario: WAV file transcription
- **WHEN** a WAV audio file is provided for transcription
- **THEN** the audio samples are extracted and normalized to Float32
- **AND** passed to whisper.cpp for inference

### Requirement: Transcription Provider Protocol
The system SHALL abstract transcription behind a protocol to support both local and cloud backends.

#### Scenario: Provider selection
- **WHEN** transcription is requested
- **THEN** the coordinator selects the appropriate provider based on current mode setting

### Requirement: Multilingual Support
The system SHALL support multiple languages when a multilingual model is selected.

#### Scenario: Language selection available
- **WHEN** a multilingual model is active (e.g., not `.en` suffix)
- **THEN** language picker is available in Settings
- **AND** user can select from 50+ supported languages

#### Scenario: English-only model
- **WHEN** an English-only model is active (e.g., `tiny.en`)
- **THEN** language picker is hidden or shows only English

