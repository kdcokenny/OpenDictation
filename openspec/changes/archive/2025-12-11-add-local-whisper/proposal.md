# Change: Add Local Whisper Model Support

## Why

OpenDictation currently requires an API key and internet connection to function, creating friction for first-time users and privacy-conscious users. Adding local Whisper model support enables zero-config, offline-first dictation that "just works" out of the box—like opening a new MacBook.

## What Changes

- **Bundled default model**: Ship `ggml-tiny.en.bin` (~75MB) in the app bundle for instant first-run experience
- **Deletable bundled model**: Users can remove the bundled model and replace with downloaded alternatives
- **Local/Cloud mode toggle**: Settings UI to switch between offline local transcription and cloud API
- **Model management**: Download additional models from Hugging Face, delete unused models
- **Voice Activity Detection (VAD)**: Bundle Silero VAD model for automatic silence/noise filtering
- **Output filtering**: Remove hallucinations (`[BLANK_AUDIO]`, `[MUSIC]`) and filler words (uh, um)
- **Multilingual support**: Support 50+ languages via whisper.cpp (model-dependent)
- **Advanced settings**: Power users can access temperature, initial prompt, etc. in collapsed section

## Impact

- **Affected specs**: New `local-transcription` and `model-management` capabilities
- **Affected code**:
  - New: `Whisper/` directory (LibWhisper, WhisperContext, VADModelManager)
  - New: `LocalTranscriptionService.swift`, `ModelManager.swift`
  - Modified: `TranscriptionService.swift` → `CloudTranscriptionService.swift`
  - Modified: `SettingsView.swift` (Local/Cloud toggle, model picker)
- **Build changes**: whisper.cpp XCFramework via Makefile
- **Bundle size**: +75MB (tiny.en model) +2MB (Silero VAD)
- **User experience**: Open app → works immediately → customize in Settings if desired
