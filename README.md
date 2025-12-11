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

- macOS 13.0 (Ventura) or later
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

2. Build and run
   ```bash
   swift build
   ```

## Usage

1. Press `Option + Space` to start recording
2. Speak your text
3. Press `Option + Space` again to stop and transcribe
4. Text is automatically inserted (or copied to clipboard)

Press `Escape` at any time to cancel.

## Configuration

Open the Settings window from the menu bar to configure:

- **Hotkey:** Customize the activation shortcut
- **API Key:** Your OpenAI-compatible API key
- **Model:** Select transcription model
- **Language:** Choose from 57 supported languages or auto-detect

## Architecture

| Component | Technology |
| :--- | :--- |
| Interface | SwiftUI + AppKit (`NSPanel` with non-activating behavior) |
| Audio | AVFoundation with real-time level metering |
| Transcription | Local Whisper / OpenAI-compatible APIs |
| Text Insertion | Accessibility API with clipboard fallback |

## License

MIT
