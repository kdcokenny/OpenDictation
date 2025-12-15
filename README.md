<div align="center">
  <h1>Open Dictation</h1>
  <p><strong>Voice-to-text for any macOS app, powered by local or cloud AI</strong></p>

  <p>
    <a href="https://github.com/kdcokenny/OpenDictation/releases/latest"><img src="https://img.shields.io/badge/download-latest-brightgreen?style=for-the-badge" alt="Download"></a>
    <img src="https://img.shields.io/badge/platform-macOS-blue?style=for-the-badge" alt="Platform">
    <img src="https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=for-the-badge" alt="Requirements">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow?style=for-the-badge" alt="License"></a>
  </p>

  <!-- TODO: Add screenshot or demo GIF -->
  <!-- <img src="screenshot.png" width="600" alt="Open Dictation Demo"> -->
</div>

---

## Installation

### Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1 or later)
- **MacBook with notch** for visual UI (2021 MacBook Pro, 2022+ MacBook Air)

> [!IMPORTANT]
> Open Dictation requires **Accessibility** and **Microphone** permissions.
> You'll be prompted to grant these on first launch.

> [!NOTE]
> **Non-notch Macs**: Dictation still works but without visual feedback. You'll hear audio cues (start/stop sounds) to indicate state. If you'd like visual UI support for non-notch Macs, please [file a feature request](https://github.com/kdcokenny/OpenDictation/issues/new).

### Download

[![Download DMG](https://img.shields.io/badge/Download-DMG-blue?style=for-the-badge&logo=apple)](https://github.com/kdcokenny/OpenDictation/releases/latest/download/OpenDictation.dmg)

Download the DMG, open it, and drag Open Dictation to your Applications folder.

### First Launch

Since Open Dictation is distributed outside the Mac App Store, macOS may show a warning or say the app is "damaged."

**To fix this**, run this command in Terminal:

```bash
xattr -rd com.apple.quarantine /Applications/OpenDictation.app
```

This removes the quarantine flag that macOS adds to downloaded apps. You only need to do this once.

### Homebrew

```bash
# Coming soon
# brew install --cask open-dictation
```

### Build from Source

```bash
git clone https://github.com/kdcokenny/OpenDictation.git
cd OpenDictation
make setup  # Downloads models and builds whisper.cpp
make build  # Builds the app
make run    # Run the app
```

See `make help` for all available targets.

---

## Usage

1. Press **Option + Space** to start recording
2. Speak your text
3. Press **Option + Space** again to stop and transcribe
4. Text is automatically inserted into the active field

Press **Escape** at any time to cancel.

---

## Configuration

Open **Settings** from the menu bar icon to configure:

| Setting | Description |
|---------|-------------|
| **Hotkey** | Customize the activation shortcut |
| **Mode** | Local (offline, private) or Cloud (API-based) |
| **API Key** | Your OpenAI-compatible API key (Cloud mode) |
| **Language** | 50+ languages or auto-detect |

### Model Storage

Whisper models are stored in `~/Library/Application Support/com.opendictation/Models/`. The app automatically selects the best model for your system.

---

## Features

- **Dynamic Island-style UI** — Notch-integrated dictation panel on MacBooks with notch
- **Local transcription** — Run Whisper models on-device for privacy
- **Cloud transcription** — Connect to OpenAI, Groq, or any compatible API
- **Smart text insertion** — Automatically pastes into the active field
- **Audio feedback** — Start/stop sounds matching macOS conventions
- **Automatic updates** — Stay up to date via Sparkle

---

## License

[MIT](LICENSE)
