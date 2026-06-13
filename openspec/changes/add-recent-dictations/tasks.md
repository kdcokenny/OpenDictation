## 1. Implementation
- [x] 1.1 Add `DictationHistoryEntry` and `DictationHistoryService` with session-only in-memory entries, count pruning, TTL pruning, audio file ownership, and cleanup-on-quit.
- [x] 1.2 Update the recording/transcription orchestration so each completed attempt creates or updates a history entry before the recorder temp file is deleted.
- [x] 1.3 Update text insertion to return an explicit delivery result instead of overloading `Bool`.
- [x] 1.4 Update state-machine/app wiring so transcription success, empty output, transcription failure, copied-only fallback, and delivery failure update the matching history entry.
- [x] 1.5 Add retry support that reuses the saved audio URL and original `ContextProfile` through `TranscriptionCoordinator` with current user settings.
- [x] 1.6 Add a SwiftUI `Recent` window with rows for timestamp/context/status, transcript preview, `Copy`, and `Retry` controls.
- [x] 1.7 Add a `Recent...` status item menu entry that opens or focuses the Recent window.
- [x] 1.8 Clean up retained audio files during TTL prune, manual clear if implemented, and app termination.

## 2. Tests
- [x] 2.1 Add unit tests for history entry insertion, max-count pruning, TTL pruning, and file deletion.
- [x] 2.2 Add unit tests for retry updating an existing entry from failed/empty to succeeded or failed.
- [x] 2.3 Update text insertion tests for explicit delivery results.
- [x] 2.4 Update state-machine tests to distinguish copied-only fallback from delivery failure.

## 3. Validation
- [x] 3.1 Run `openspec validate add-recent-dictations --strict`.
- [x] 3.2 Run `make test`.
- [x] 3.3 Run `make build`.
- [ ] 3.4 Manual QA: successful dictation appears in Recent and Copy copies the transcript.
- [ ] 3.5 Manual QA: force transcription failure, verify audio remains available until TTL/quit and Retry regenerates using current settings.
- [ ] 3.6 Manual QA: revoke Accessibility permission, dictate, verify delivery is copied-only and Recent exposes Copy.
- [ ] 3.7 Manual QA: quit and relaunch, verify prior audio/transcripts do not reappear.
