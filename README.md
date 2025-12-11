# Open Dictation

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift&logoColor=white)](https://developer.apple.com/swift/)

A lightweight, native macOS dictation app powered by your choice of transcription backend.

Open Dictation brings voice-to-text to any application with a simple hotkey. It's designed to feel at home on macOS—a floating panel that stays out of your way, audio feedback that matches system conventions, and text insertion that just works.

## Features

- **Native Experience:** A floating `NSPanel` that appears without stealing focus, with smooth animations and system-appropriate visual design.
- **Flexible Backends:**
  - **Local:** Run Whisper models on-device for private, offline transcription.
  - **Cloud:** Connect to any OpenAI-compatible API (OpenAI, Groq, etc.) for fast, accurate results.
- **Smart Text Insertion:** Automatically pastes transcribed text into the active field. Falls back to clipboard when direct insertion isn't available.
- **Audio Feedback:** Start/stop sounds and volume ducking during recording, matching macOS conventions.

## Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+

### Permissions

Open Dictation requires:
- **Accessibility:** To detect text fields and insert transcribed text
- **Microphone:** To capture audio for transcription

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/open-dictation.git
   cd open-dictation
   ```

2. Build the whisper.cpp framework and download models
   ```bash
   make setup
   ```
   This clones whisper.cpp, builds the XCFramework, and downloads:
   - `ggml-tiny.bin` (~75MB) - Default transcription model (multilingual)
   - `ggml-silero-v5.1.2.bin` (~2MB) - Voice Activity Detection model

3. Build the app
   ```bash
   make build
   ```

4. Run
   ```bash
   make run
   ```

**Quick start:** Run `make all` to do steps 2-3 in one command.

See `make help` for all available targets.

## Usage

1. Press `Option + Space` to start recording
2. Speak your text
3. Press `Option + Space` again to stop and transcribe
4. Text is automatically inserted (or copied to clipboard)

Press `Escape` at any time to cancel.

## Configuration

Open the Settings window from the menu bar to configure:

- **Hotkey:** Customize the activation shortcut
- **Transcription Mode:** Local (offline) or Cloud (API-based)
- **API Key:** Your OpenAI-compatible API key (Cloud mode)
- **Language:** Choose from 50+ supported languages or auto-detect

### Model Storage

Downloaded Whisper models are stored in:
```
~/Library/Application Support/com.opendictation/Models/
```

The bundled `ggml-tiny` model is copied here on first launch. The app automatically selects the best model for your system. You can manually select models in Advanced Settings or delete unused ones to free disk space.

## Architecture

| Component | Technology |
| :--- | :--- |
| Interface | SwiftUI + AppKit (`NSPanel` with non-activating behavior) |
| Audio | AVFoundation with real-time level metering |
| Transcription | Local Whisper / OpenAI-compatible APIs |
| Text Insertion | Accessibility API with clipboard fallback |

## License

MIT
