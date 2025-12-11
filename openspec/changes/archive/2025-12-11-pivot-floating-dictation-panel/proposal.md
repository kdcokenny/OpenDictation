# Change: Pivot to Floating Dictation Panel

## Why

The original design attempted to replicate macOS native dictation's caret-following HUD. After research, we've determined this approach has significant limitations:

1. Cannot stream text in real-time (API limitation—must send full audio)
2. Caret position detection is fragile across diverse apps
3. Complexity of tracking cursor movement during dictation

Successful dictation utilities like Wispr Flow use a simpler pattern: a fixed-position floating panel at the bottom of the screen. This is more reliable, simpler to implement, and still feels native when executed well with proper materials and animations.

## What Changes

- **REMOVED**: Caret-following positioning (`DictationCaretPanel`, `DictationCaretView`, `CursorService`)
- **REMOVED**: CursorBounds package dependency
- **MODIFIED**: `DictationOverlayPanel` → Fixed bottom-center positioning with macOS 26 Liquid Glass
- **MODIFIED**: `DictationHUDView` → Replaced with 5-bar waveform visualization
- **ADDED**: `WaveformView` for audio-reactive bar visualization
- **ADDED**: `TextFieldDetector` service for input field detection
- **ADDED**: Sine wave animation for processing state
- **ADDED**: Shake animation for empty transcription
- **ADDED**: Error state handling (red tint, icon, sound)
- **ADDED**: Fast-path optimization (skip processing animation if <0.5s)
- **ADDED**: Graceful fallback to clipboard-only when not in text field

## Impact

- **Affected specs**: `dictation-ui` (new capability spec)
- **Affected code**:
  - `Sources/OpenDictation/Views/` (panel and view changes)
  - `Sources/OpenDictation/Services/` (new TextFieldDetector, modified insertion)
  - `Package.swift` (remove CursorBounds if no longer needed)
- **User-facing**: Visual design changes, same activation flow (toggle hotkey)
- **Breaking**: None (this is the initial implementation)
