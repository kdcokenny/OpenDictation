# Simplify Text Insertion Logic

## Goal
Refactor the text insertion logic to align with Apple's "just work" philosophy by removing unreliable detection checks and complex accessibility-based insertion methods. The system should universally rely on the standard Clipboard + Paste (Cmd+V) mechanism.

## Context
Currently, `OpenDictation` attempts to detect if a text field is focused using `TextFieldDetector` (via Accessibility API) and only pastes if detected. If not detected, it copies to the clipboard without pasting. This fails in many non-native apps (Electron, browsers) where detection is unreliable but pasting works fine.

Research into top macOS dictation apps (VoiceInk, etc.) shows that the industry standard is to "Always Paste" using `CGEvent` to simulate `Cmd+V`, regardless of focused element state.

## Changes
1.  **Remove `TextFieldDetector`**: Delete the entire class as it is unreliable and unnecessary for the "always paste" strategy.
2.  **Simplify `TextInsertionService`**:
    *   Remove `Accessibility` insertion logic.
    *   Remove conditional logic based on detection.
    *   Implement "Always Paste" using Clipboard + `CGEvent` (Cmd+V).
    *   Add clipboard restoration (save -> paste -> restore).
3.  **Update Consumers**: Update `AppDelegate` and `DictationStateMachine` to handle the simplified flow (mostly effectively always successful insertion).

## Risk
- **Paste in non-text areas**: If the user is not in a text field, `Cmd+V` might trigger an app-specific paste action or do nothing. This is considered acceptable behavior (standard system behavior).
- **Clipboard interference**: Brief replacement of clipboard content. Mitigated by saving and restoring the clipboard, which is a standard practice in these tools.
