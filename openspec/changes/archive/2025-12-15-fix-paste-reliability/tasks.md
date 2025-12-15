# Tasks: Fix Paste Reliability

## 1. Core Timing Fixes
- [x] 1.1 Change `CGEventSource` state from `.hidSystemState` to `.combinedSessionState` in `simulatePaste()`
- [x] 1.2 Add 50ms synchronous delay after `setString` before calling `simulatePaste()`
- [x] 1.3 Change clipboard restoration from async to synchronous with 150ms delay after paste

## 2. Event Simulation Hardening
- [x] 2.1 Configure event source suppression to prevent input interference during paste
- [x] 2.2 Refactor `simulatePaste()` to post explicit Command key down/up events (4 events total)
- [x] 2.3 Ensure proper event sequencing: Cmd down -> V down -> V up -> Cmd up

## 3. Clipboard Preservation
- [x] 3.1 Refactor clipboard saving to capture all pasteboard types and data (not just string)
- [x] 3.2 Implement `savePasteboardContents()` helper that iterates all types and saves data
- [x] 3.3 Implement `restorePasteboardContents()` helper that restores all saved types
- [x] 3.4 Add verification that clipboard content was set correctly before pasting

## 4. Concurrency Control
- [x] 4.1 Add static `isInserting` flag with `NSLock` protection to `TextInsertionService`
- [x] 4.2 Guard `insertText()` to reject concurrent calls while paste is in progress
- [x] 4.3 Ensure flag is always reset on all exit paths (use defer)

## 5. Validation
- [x] 5.1 Manual test: Rapid double-tap of hotkey should not corrupt clipboard
- [x] 5.2 Manual test: Copy image, dictate, verify image is restored to clipboard
- [x] 5.3 Manual test: Dictate in various apps (Terminal, Safari, VS Code, Slack) and verify paste works
- [x] 5.4 Manual test: Verify no regression - normal dictation flow still works
- [x] 5.5 Manual test: Type immediately after dictation completes - should not interfere

## Dependencies
- Section 1 tasks can be done in parallel
- Section 2 tasks depend on 1.1 (need event source created first)
- Section 3 is independent of sections 1-2
- Section 4 is independent of sections 1-3
- Section 5 requires all other sections complete
