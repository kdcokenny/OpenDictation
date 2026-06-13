## ADDED Requirements
### Requirement: Session-Scoped Recent Dictations
The system SHALL keep a short-term Recent list of completed dictation attempts for the current app session.

#### Scenario: Successful attempt is retained
- **WHEN** a dictation attempt produces a non-empty transcript
- **AND** text delivery is attempted
- **THEN** the attempt appears in Recent
- **AND** the entry includes its creation time, original context profile, transcript text, transcription status, and delivery status

#### Scenario: Failed transcription is retained
- **WHEN** a dictation attempt records audio
- **AND** transcription fails
- **THEN** the attempt appears in Recent
- **AND** the entry includes its creation time, original context profile, copied audio URL, and failure message
- **AND** the entry offers retry while the audio file is still retained

#### Scenario: Empty transcription is retained
- **WHEN** transcription completes with empty or whitespace-only text
- **THEN** the attempt appears in Recent
- **AND** the entry is marked as empty
- **AND** the entry offers retry while the audio file is still retained

#### Scenario: Apparent success is retained
- **WHEN** transcription and delivery both appear to succeed
- **THEN** the attempt still appears in Recent
- **AND** the user can copy the transcript from Recent

### Requirement: Short-Term Retention
The system SHALL retain Recent entries only for short-term recovery during the current app session.

#### Scenario: Entry count exceeds limit
- **WHEN** adding an entry would exceed the maximum Recent entry count
- **THEN** the oldest entries are removed until the count is within the limit
- **AND** audio files for removed entries are deleted

#### Scenario: Entry exceeds TTL
- **WHEN** an entry is older than the configured TTL
- **THEN** the entry is removed from Recent
- **AND** its retained audio file is deleted

#### Scenario: App quits
- **WHEN** Open Dictation terminates
- **THEN** all retained Recent audio files are deleted
- **AND** Recent entries are not restored on the next launch

### Requirement: Audio Ownership For Replay
The system SHALL copy recorded audio into app-owned short-term storage before deleting the recorder temporary file.

#### Scenario: Recording stops
- **WHEN** recording stops and produces an audio file URL
- **THEN** the history service claims the audio by copying it to app-owned short-term storage
- **AND** replay uses the copied audio file, not the recorder temporary file

#### Scenario: Audio claim fails
- **WHEN** the history service cannot copy the audio file
- **THEN** the original dictation flow continues
- **AND** the Recent entry records that retry audio is unavailable
- **AND** the failure is logged

### Requirement: Retry Transcription
The system SHALL allow users to retry transcription for Recent entries that still have retained audio.

#### Scenario: Retry uses current settings
- **WHEN** the user clicks Retry for a Recent entry
- **THEN** the system retranscribes the retained audio through the current transcription mode, model, language, and API settings
- **AND** the retry uses the entry's original context profile

#### Scenario: Retry succeeds
- **WHEN** retry transcription returns non-empty text
- **THEN** the entry transcript is replaced with the new text
- **AND** the entry transcription status is marked succeeded
- **AND** the entry offers Copy

#### Scenario: Retry fails
- **WHEN** retry transcription fails
- **THEN** the entry remains in Recent
- **AND** the entry displays the latest failure message
- **AND** retry remains available while retained audio exists

#### Scenario: Retained audio expired
- **WHEN** the user views an entry whose retained audio has expired or been deleted
- **THEN** Retry is unavailable
- **AND** any available transcript remains copyable until the entry itself is pruned

### Requirement: Copy Transcript
The system SHALL allow users to copy available transcript text from Recent.

#### Scenario: Copy available transcript
- **WHEN** a Recent entry has non-empty transcript text
- **AND** the user clicks Copy
- **THEN** the transcript text is written to the general pasteboard

#### Scenario: No transcript available
- **WHEN** a Recent entry has no non-empty transcript
- **THEN** Copy is unavailable

### Requirement: No Paste-Again In V1
The system SHALL NOT provide paste-again from the Recent window in v1.

#### Scenario: Recent entry has transcript
- **WHEN** a Recent entry has transcript text
- **THEN** the available recovery action is Copy
- **AND** the system does not attempt to paste into the previously active app from the Recent window

### Requirement: Delivery Status Tracking
The system SHALL record text delivery outcome separately from transcription outcome.

#### Scenario: Text inserted
- **WHEN** text insertion is attempted and paste is successfully initiated
- **THEN** the Recent entry delivery status is marked inserted

#### Scenario: Clipboard-only fallback
- **WHEN** text insertion cannot paste but can copy the transcript to the clipboard
- **THEN** the Recent entry delivery status is marked copied-only
- **AND** the transcript remains available for Copy in Recent

#### Scenario: Delivery failure
- **WHEN** text insertion cannot verify clipboard setup or cannot complete delivery
- **THEN** the Recent entry delivery status is marked failed
- **AND** the transcript remains available for Copy in Recent
