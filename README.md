<div align="center">
  <h1>Open Dictation</h1>
  <p><strong>A lightweight, notch-integrated dictation utility for macOS.</strong></p>

  <p>
    <a href="https://github.com/kdcokenny/OpenDictation/releases/latest"><img src="https://img.shields.io/badge/download-latest-brightgreen?style=for-the-badge" alt="Download"></a>
    <img src="https://img.shields.io/badge/platform-macOS-blue?style=for-the-badge" alt="Platform">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow?style=for-the-badge" alt="License"></a>
  </p>

  <img src="https://github.com/user-attachments/assets/ff4c6660-6265-40e1-b9be-91d36d7a69d7" width="450" alt="Open Dictation Demo showing Notch UI and instant text insertion">
</div>

---

## Why Open Dictation?

Native macOS dictation is unreliable—it frequently times out, fails to start, and struggles with technical jargon. Existing AI alternatives often demand $10+/month subscriptions just to use your own Mac's hardware.

Open Dictation is a **headless utility** designed to fix this.

- **Zero Subscriptions:** Run Whisper models locally on your Neural Engine or use your own API keys for cloud processing.
- **Notch Integration:** Visual feedback lives in the "Dynamic Island" area. No floating windows blocking your code.
- **Developer Ready:** Doesn't time out while you're thinking. Handles camelCase, file paths, and technical terms natively.
- **No Bloat:** 100% focused on getting text to your cursor. No sidebars, no proprietary "clouds," no nonsense.

---

## Installation

### Requirements
- macOS 14+ (Sonoma or later)
- Apple Silicon Mac (M1, M2, M3, M4)
- **MacBook with notch** for the integrated UI (Dictation still works on non-notch Macs via audio cues).

### Quick Start
1. **[Download the latest DMG](https://github.com/kdcokenny/OpenDictation/releases/latest/download/OpenDictation.dmg)**
2. Drag to Applications.
3. Open Terminal and run this to bypass the quarantine flag (required for non-signed builds):
   ```bash
   xattr -rd com.apple.quarantine /Applications/OpenDictation.app
   ```

4. Launch and grant **Accessibility** and **Microphone** permissions.

---

## Usage

* **Option + Space**: Start recording.
* **Speak**: The Notch will provide visual feedback while you talk.
* **Option + Space**: Stop recording. The transcribed text is inserted at your cursor instantly.
* **Escape**: Cancel the current recording.

---

## Configuration

| Feature | Description |
| --- | --- |
| **Local Mode** | Uses Whisper models on-device. No data leaves your Mac. |
| **Cloud Mode** | Connect to OpenAI, Groq, or any OpenAI-compatible API. |
| **BYOK** | "Bring Your Own Key"—pay the raw API cost ($0.003) instead of a platform markup. |
| **Auto-Paste** | Directly inserts text into the active field (IDE, Slack, Browser). |

---

## Model Support

The app automatically manages Whisper models stored in:
`~/Library/Application Support/com.opendictation/Models/`

---

## License

[MIT](LICENSE)
