# Change: Add Automatic Model Selection

## Why
The current UI requires users to manually select a quality tier (Fast/Balanced/Best Quality), which adds unnecessary friction and doesn't match Apple's native dictation experience. Apple's dictation "just works" - it auto-detects system capabilities and handles models invisibly. Users shouldn't need to understand model sizes or make trade-off decisions for a basic feature.

This change brings OpenDictation closer to Apple's design philosophy: works immediately, gets better automatically, with power-user controls tucked away for those who want them.

## What Changes
- **REMOVED**: Quality selector from main Settings UI (Fast/Balanced/Best Quality rows)
- **ADDED**: System capability detection (RAM size, chip type, system language)
- **ADDED**: Automatic model recommendation based on detected specs
- **ADDED**: Background download of recommended model (silent, non-blocking)
- **ADDED**: Seamless model switching when better model becomes available
- **MODIFIED**: Settings UI simplified - mode toggle + language picker only for basic users
- **ADDED**: Advanced tab with manual model selection for power users

## Impact
- Affected specs: `model-management`
- Affected code:
  - `Sources/OpenDictation/Views/SettingsView.swift` - Remove quality section, add Advanced tab
  - `Sources/OpenDictation/Services/ModelManager.swift` - Add auto-recommendation, background download
  - `Sources/OpenDictation/Models/PredefinedModels.swift` - Add system capability mapping
  - New file: `Sources/OpenDictation/Services/SystemCapabilities.swift` - Hardware detection

## User Experience Flow

### First Launch (Online + Wi-Fi)
1. App starts with bundled `ggml-tiny.en` model (75MB) - works immediately
2. System specs detected in background
3. If system can handle better model AND on Wi-Fi → starts silent foreground download
4. User dictates with tiny model (functional but basic accuracy)
5. When download completes → next dictation session uses better model (no restart, no notification)

*Note: Auto-upgrade downloads only occur on Wi-Fi to respect user data plans.*

### First Launch (Offline or Cellular)
1. App starts with bundled `ggml-tiny.en` model - works immediately
2. System specs detected, recommendation calculated
3. Download deferred until Wi-Fi available
4. On next launch with Wi-Fi → silent foreground download starts

### Power User Flow
1. User opens Settings → Advanced tab
2. Sees current auto-selected model and recommendation
3. Can manually select any model from dropdown
4. Can download/delete individual models
5. "Reset to Automatic" button returns to auto-selection

## Model Recommendation Matrix

| RAM | Chip | English System | Non-English |
|-----|------|----------------|-------------|
| <8GB | Any | ggml-tiny.en (75MB) | ggml-tiny (75MB) |
| 8GB | M1/M2 | ggml-base.en (142MB) | ggml-base (142MB) |
| 8GB | M3+ | ggml-large-v3-turbo-q5_0 (547MB) | ggml-large-v3-turbo-q5_0 |
| 16GB+ | Any | ggml-large-v3-turbo-q5_0 (547MB) | ggml-large-v3-turbo-q5_0 |

*Note: Model names use `ggml-` prefix per whisper.cpp convention. large-v3-turbo-q5_0 is multilingual.*


