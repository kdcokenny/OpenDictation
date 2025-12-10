# Open Dictate

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift&logoColor=white)](https://developer.apple.com/swift/)

**The native macOS dictation experience, unlocked.**

Open Dictate is a native macOS application that decouples the elegant, non-intrusive UI of Apple's built-in dictation from its closed ecosystem. It provides a pixel-perfect recreation of the native HUD while allowing developers to route audio to any inference backend—whether that is a local Whisper model for zero-latency offline use, or OpenAI-compatible APIs (Groq, OpenAI, etc.) for state-of-the-art coding assistance.

This project is built on a strict **native-first architecture**. It rejects clipboard injection and keyboard simulation hacks in favor of deep system integration via the Accessibility API.

## ✨ Features

- **1:1 Native HUD:** A floating, non-activating `NSPanel` that mimics the system UI perfectly. It appears contextually and does not steal focus from your active editor or IDE.
- **Model Agnostic:**
  - **Local Inference:** Bundled with `whisper.cpp` for high-performance, offline transcription on Apple Silicon.
  - **Cloud Inference:** Drop-in support for OpenAI-compatible endpoints (OpenAI, Groq, Anyscale) for superior accuracy and speed.
- **Contextual Positioning:** Utilizes `AXUIElement` to query the precise screen coordinates of the text caret, positioning the microphone interface exactly where you are typing.
- **Robust Text Insertion:** Bypasses the clipboard entirely. Text is inserted programmatically into the focused element using Accessibility APIs, preserving clipboard history and undo stacks.

## 🛠 Architecture

Open Dictate is built to be a reference implementation for modern macOS system utilities.

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Interface** | SwiftUI + AppKit | Uses `NSPanel` with `.nonactivatingPanel` style masks to float above windows without triggering window activation events. |
| **Inference** | Swift / C++ | Wraps `whisper.cpp` for local execution and `URLSession` for streaming API responses from cloud providers. |
| **Integration** | Accessibility API | Leverages `ApplicationServices` to read `kAXSelectedTextRangeAttribute` and write to `kAXSelectedTextAttribute`. |
| **Audio** | AVFoundation | Low-latency audio capture with real-time Voice Activity Detection (VAD). |

## 🚀 Getting Started

### Prerequisites

- macOS 13.0 (Ventura) or later.
- Xcode 15.0+.
- **Permissions:** This application functions as an Input Method. It requires **Accessibility** permissions to function.

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/open-dictate.git
