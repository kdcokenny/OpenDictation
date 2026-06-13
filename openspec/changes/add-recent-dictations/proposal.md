# Change: Add Recent Dictations Recovery

## Why
Transcription and delivery can fail in different ways: the audio may fail to generate a usable
transcript, or the transcript may be produced but not appear in the target app. Users need a
short-term recovery surface so they can retry transcription from recent audio or copy known text
without turning Open Dictation into a permanent history app.

## What Changes
- Add a session-scoped Recent window that lists recent completed dictation attempts.
- Retain short-lived copied audio files and transcript/delivery metadata for recovery.
- Allow users to retry transcription from a recent audio clip using the current transcription mode,
  model, language, and API settings while preserving the original context profile.
- Allow users to copy an available transcript from Recent.
- Add a `Recent...` item to the status item menu.
- Keep retention short-term: prune by count and TTL during the session and delete retained audio
  when the app quits.

## Impact
- Affected specs: dictation-history, menu-bar
- Affected code:
  - `OpenDictation/App/AppDelegate.swift`
  - `OpenDictation/Core/Services/RecordingService.swift`
  - `OpenDictation/Core/Services/TranscriptionCoordinator.swift`
  - `OpenDictation/Core/Services/TextInsertionService.swift`
  - `OpenDictation/Core/Services/DictationStateMachine.swift`
  - `OpenDictation/Views/RecentDictationsView.swift`
  - `OpenDictationTests/*`

## Decisions
- Recent records all completed attempts, including apparent successes, because target-app paste
  failures can be silent.
- Retention is current app session only with a small in-session TTL. The implementation should use
  30 minutes unless product feedback chooses a tighter value before implementation.
- Retry uses the user's current transcription settings and the original `ContextProfile`.
- V1 provides copy and retry actions only. Paste-again from the Recent window is out of scope.
