## Context
Open Dictation currently records to a temporary WAV file, transcribes it, attempts text delivery,
and deletes the recording after the transcription task finishes. That makes recovery impossible
when the transcription backend fails, returns an unusable result, or text delivery fails after a
valid transcript exists.

The existing provider boundary already accepts `audioURL` plus `ContextProfile`, so replay does
not need a provider-specific path. The missing piece is an app-owned, short-lived recovery owner
that claims audio before `RecordingService.deleteRecording()` removes it.

## Goals / Non-Goals
- Goals:
  - Give users a menu-accessible `Recent` window for short-term recovery.
  - Preserve enough information to retry transcription and copy known transcript text.
  - Keep audio/transcript retention session-scoped and automatically pruned.
  - Make transcription failure and delivery failure visible as distinct recovery states.
- Non-Goals:
  - No long-term transcript/audio history.
  - No paste-again action from the Recent window in v1.
  - No per-entry provider/model picker in v1.
  - No cloud-only replay path.

## Decisions
- Decision: Add a `DictationHistoryService` as the recovery source of truth.
  - It owns recent entries, copied audio file URLs, status updates, and pruning.
  - It should be an `ObservableObject` on `MainActor` so the SwiftUI window can observe updates
    without inventing another event bus.
- Decision: Copy audio into an app-owned cache folder when recording stops.
  - The history service must claim the file before existing cleanup deletes the recorder's temp
    file.
  - Audio filenames should be entry IDs, not transcript text or target-app names.
- Decision: Store entries in memory and files only for the current session.
  - The service prunes entries older than the TTL and removes files on app termination.
  - No transcript database, no UserDefaults persistence, and no automatic restoration after launch.
- Decision: Retry uses `TranscriptionCoordinator.shared.transcribe(audioURL:context:)`.
  - This preserves provider abstraction and lets current settings determine local/cloud behavior.
  - The original context profile remains attached so technical/prose/code prompting remains
    consistent with where the dictation was captured.
- Decision: Replace the overloaded insertion Boolean with an explicit delivery result during
  implementation.
  - The history entry should distinguish `inserted`, `copiedOnly`, and `failed` delivery outcomes.
  - This avoids treating accessibility fallback copy as the same thing as clipboard verification
    failure.

## Data Model
Suggested entry shape:

```swift
struct DictationHistoryEntry: Identifiable, Equatable {
  enum TranscriptionStatus: Equatable {
    case pending
    case succeeded(String)
    case empty
    case failed(String)
    case retrying
  }

  enum DeliveryStatus: Equatable {
    case notAttempted
    case inserted
    case copiedOnly
    case failed(String)
  }

  let id: UUID
  let createdAt: Date
  let audioURL: URL
  let context: ContextProfile
  var transcriptionStatus: TranscriptionStatus
  var deliveryStatus: DeliveryStatus
}
```

The exact names can change during implementation, but the ownership boundary should not: the
history service owns retention and status; transcription providers only transcribe; text insertion
only reports delivery.

## Risks / Trade-offs
- Privacy risk: keeping audio even briefly can surprise users.
  - Mitigation: session-only storage, automatic TTL pruning, delete on quit, and no relaunch
    persistence.
- Silent paste failures are not directly observable.
  - Mitigation: record all attempts so users can copy even when the app believed insertion worked.
- Cache-file cleanup can leak files if only in-memory pruning is implemented.
  - Mitigation: unit-test file deletion on prune/clear and call cleanup from app termination.
- Retry can produce a different transcript if settings changed.
  - Mitigation: this is intentional; the UI/spec should make retry mean regenerate with current
    settings.

## Rollback
The feature is additive. Rollback can remove the `Recent...` menu item and history service wiring.
Any leftover cache directory can be deleted on next launch as defensive cleanup.

## Open Questions
- Confirm final TTL before implementation. Default plan: 30 minutes within the current app session.
