<div align="center">
  <h1>Open Dictation</h1>
  <p><strong>A native dictation utility for Apple silicon Macs.</strong></p>

  <p>
    <a href="https://github.com/kdcokenny/OpenDictation/releases/latest"><img src="https://img.shields.io/badge/download-latest-brightgreen?style=for-the-badge" alt="Download"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=for-the-badge" alt="macOS 14 or later">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow?style=for-the-badge" alt="License"></a>
  </p>

  <img src="https://github.com/user-attachments/assets/ff4c6660-6265-40e1-b9be-91d36d7a69d7" width="450" alt="Open Dictation recording from the MacBook notch">
</div>

Open Dictation records from a chosen microphone, transcribes the finished recording, and pastes the result at the cursor. Its notch panel shows recording and transcription state on supported MacBooks. Macs and displays without a notch use audio feedback.

## Features

- Whisper runs locally and remains the default speech engine.
- Parakeet TDT v2 handles English, while Parakeet TDT v3 supports 25 European languages. Both are optional and run locally through FluidAudio 0.15.6.
- Parakeet models download only after you choose **Download and Prepare Model**. Parakeet prewarming uses installed models without downloading. Whisper retains its automatic model selection and upgrade behavior.
- The global shortcut supports press-to-start/press-to-stop and hold-to-talk modes.
- Microphone choices use stable Core Audio device identifiers. If a selected device is missing, recording stops with a clear error instead of changing inputs.
- A personal dictionary supplies recognition hints to Whisper and compatible cloud services. Literal replacements work with every engine, including Parakeet.
- Transcript cleanup is deliberately narrow. It removes known speech-to-text control and noise markers without broad punctuation rewrites. Optional filler-word removal is off by default and avoids rewriting fragments inside other words.
- Cloud presets cover OpenAI GPT Transcribe, GPT-4o mini Transcribe, OpenAI Whisper, and Groq Whisper Turbo. You can also set an OpenAI-compatible base URL and model name.
- If Accessibility access is available, Open Dictation pastes at the cursor and restores the previous clipboard contents. Without it, the transcript stays on the clipboard.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon Mac
- Microphone permission
- Accessibility permission for automatic paste

## Install

1. [Download the latest DMG](https://github.com/kdcokenny/OpenDictation/releases/latest/download/OpenDictation.dmg).
2. Drag Open Dictation to Applications.
3. For an unsigned build, remove its quarantine attribute:

   ```bash
   xattr -rd com.apple.quarantine /Applications/OpenDictation.app
   ```

4. Launch the app and grant the requested permissions.

## Use

The default shortcut is **Option + Space**. In toggle mode, press once to record and again to transcribe. In hold mode, keep the shortcut down while speaking and release it to transcribe. Press **Escape** to cancel an active dictation.

Open Settings to choose a microphone, shortcut, activation mode, language, local engine, or cloud service. Whisper models are stored under:

```text
~/Library/Application Support/com.opendictation/Models/
```

See [dictation validation](docs/dictation-validation.md) for the manual acceptance and benchmark protocol. Third-party code and model attribution is listed in [third-party notices](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE)
