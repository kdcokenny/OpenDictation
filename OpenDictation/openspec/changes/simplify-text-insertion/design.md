# Design: Universal Text Insertion

## Motivation
The current "detection-first" approach for text insertion is unreliable. It fails to detect text fields in many modern applications (Electron, Chrome, etc.), leading to a poor user experience where dictation completes but no text appears.

Research into industry-standard tools (VoiceInk, etc.) consistently points to a "Universal Paste" strategy as the most robust solution for macOS dictation tools.

## Architecture Change

### Before
```
TextFieldDetector -> (Is Text Field?)
    YES -> Try Accessibility Insert -> (Fallback) -> Paste
    NO  -> Copy to Clipboard only
```

### After
```
Always -> Save Clipboard -> Paste (Cmd+V) -> Restore Clipboard
```

## Considerations

### Clipboard Restoration
- **Mechanism**: Save current clipboard state before pasting, then restore it after a short delay.
- **Timing**: VoiceInk uses 1.5s, but modern macOS (App Silicon) is faster. We will start with 150ms and can tune if needed.
- **Format**: We should save all clipboard types to ensure a full restoration.

### Accessibility Permissions
- We still need `AXIsProcessTrusted()` check because `CGEvent.post` requires it to synthesize keystrokes.
- If permission is missing, we gracefully fall back to "Copy to Clipboard" only.

### Dead Code Removal
- `TextFieldDetector` is entirely removed.
- `InsertionResult` enum can be simplified or just return a Boolean success.
