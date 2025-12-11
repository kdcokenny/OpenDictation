# Tasks: Add Local Whisper Model Support

## 1. Build Infrastructure

- [x] 1.1 Create `Makefile` with whisper.cpp build targets
  - Clone whisper.cpp, run `./build-xcframework.sh`
- [x] 1.2 Add whisper.xcframework to Xcode project (Package.swift)
- [x] 1.3 Bundle models in `Resources/Models/`:
  - `ggml-tiny.en.bin` (~75MB)
  - `ggml-silero-v5.1.2.bin` (~2MB) - VAD model
- [x] 1.4 Update `.gitignore` for `deps/` directory

## 2. Whisper Integration Layer

- [x] 2.1 Create `Services/Whisper/LibWhisper.swift`
  - Swift wrapper for whisper.cpp C API
  - WhisperContext actor for thread safety
- [x] 2.2 Create `Services/Whisper/WhisperError.swift`
- [x] 2.3 Create `Services/Whisper/VADModelManager.swift`
  - Return bundled Silero model path
- [x] 2.4 Create `Services/TranscriptionOutputFilter.swift`
  - Remove `[BLANK_AUDIO]`, `[MUSIC]`, filler words

## 3. Model Management

- [x] 3.1 Create `Models/WhisperModel.swift`
  - Simplified: name, displayName, size, downloadURL, isBundled
- [x] 3.2 Create `Models/PredefinedModels.swift`
  - Include: tiny.en, base.en, large-v3-turbo-q5_0
  - Include language dictionary for multilingual support
- [x] 3.3 Create `Services/ModelManager.swift`
  - Download with progress, delete, load/unload
  - Handle bundled model copy on first launch

## 4. Transcription Service Refactor

- [x] 4.1 Create `Services/TranscriptionProvider.swift` protocol
  ```swift
  protocol TranscriptionProvider {
      func transcribe(audioURL: URL) async throws -> String
  }
  ```
- [x] 4.2 Rename `TranscriptionService.swift` → `CloudTranscriptionProvider.swift`
  - Implement `TranscriptionProvider` protocol
- [x] 4.3 Create `Services/LocalTranscriptionProvider.swift`
  - Implement `TranscriptionProvider` protocol
  - Apply output filter after transcription
- [x] 4.4 Create `Services/TranscriptionCoordinator.swift`
  - Select provider based on settings (local/cloud mode)
  - Update `DictationStateMachine` to use coordinator

## 5. Settings UI

- [x] 5.1 Add `transcriptionMode` to UserDefaults
  - Enum: `.local`, `.cloud`
  - Default: `.local`
- [x] 5.2 Update `SettingsView.swift` with Local/Cloud toggle
- [x] 5.3 Add Local section:
  - Model picker (downloaded models with size)
  - Download button for undownloaded models
  - Delete button for non-bundled models
  - Language picker (when multilingual model selected)
- [x] 5.4 Move existing API config to Cloud section
- [x] 5.5 Add Advanced section (collapsed by default):
  - Temperature slider (0-1)
  - Initial prompt text field
  - Translate to English toggle

## 6. First-Run Setup

- [x] 6.1 Add bundled model copy logic in `AppDelegate`
  - Copy `ggml-tiny.en.bin` from bundle to Application Support on first launch
  - Set as default model
- [x] 6.2 Set `transcriptionMode = .local` on first launch if no API key

## 7. Testing

- [x] 7.1 Test instant first-run (no network)
- [x] 7.2 Test model download and switching
- [x] 7.3 Test bundled model deletion and replacement
- [x] 7.4 Test Local/Cloud mode toggle
- [x] 7.5 Test output filtering (verify no `[BLANK_AUDIO]` in output)

## 8. Documentation

- [x] 8.1 Update `README.md` with whisper.cpp build steps
- [x] 8.2 Document model storage location

## Dependencies

```
1.x (Build) → 2.x (Whisper layer) → 3.x (Model management) → 4.x (Service refactor)
                                                            ↓
                                                         5.x (Settings UI)
                                                            ↓
                                                         6.x (First-run)
```

## Parallelizable

- 1.x and 3.1-3.2 can run in parallel (build infra + model definitions)
- 2.x and 5.1 can run in parallel (whisper layer + settings state)
- 5.x UI work can start once 4.x protocol is defined
