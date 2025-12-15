# Change: Fix Paste Reliability Issues

## Why
Users report that dictated text sometimes fails to paste, with the previous clipboard content being pasted instead. This is a race condition caused by timing issues between clipboard operations and paste simulation, as well as improper CGEventSource configuration.

Analysis of 5 popular macOS dictation apps (OpenSuperWhisper, voicetypr, AudioWhisper, Whispera, tambourine-voice) revealed several hardening techniques our implementation lacks.

## What Changes
- **CGEventSource State**: Change from `.hidSystemState` to `.combinedSessionState` for proper event coordination
- **Timing**: Add synchronous delays before paste (50ms clipboard stabilization) and before clipboard check/restore (100-150ms)
- **Clipboard Preservation**: Save all pasteboard types (not just string) to avoid losing images/URLs
- **Concurrency Control**: Add atomic flag to prevent overlapping paste operations
- **Robustness**: Verify clipboard content was set before simulating paste

## Impact
- Affected specs: `text-insertion` (new capability), `dictation-ui` (text field detection requirements already modified)
- Affected code: `TextInsertionService.swift`
- Risk: Minimal - changes are defensive improvements to existing behavior
