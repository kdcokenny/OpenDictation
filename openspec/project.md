# Project Context

## Purpose
Open Dictation is a native macOS application that decouples Apple's built-in dictation UI from its closed ecosystem. It provides a pixel-perfect recreation of the native HUD while allowing developers to route audio to any inference backend—local Whisper models for offline use, or OpenAI-compatible APIs (Groq, OpenAI, etc.) for cloud-based transcription.

**Goals:**
- Deliver a 1:1 native dictation HUD experience
- Support both local (whisper.cpp) and cloud inference backends
- Use deep system integration via Accessibility API (no clipboard hacks)
- Position the microphone interface contextually at the text caret

## Tech Stack
- **Language:** Swift 5.9
- **UI Framework:** SwiftUI + AppKit (`NSPanel` with `.nonactivatingPanel`)
- **Local Inference:** whisper.cpp (C++ wrapped in Swift)
- **Cloud Inference:** URLSession for OpenAI-compatible API streaming
- **Audio:** AVFoundation with Voice Activity Detection (VAD)
- **System Integration:** Accessibility API (`ApplicationServices`, `AXUIElement`)
- **Build:** Xcode 15.0+
- **Target:** macOS 14.0 (Sonoma) or later

## Project Conventions

### Code Style
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use **SwiftLint** for automated style enforcement (Airbnb-inspired config)
- **2-space indentation**, 100 character line width
- Use `///` doc comments (not `/** */` block comments)
- Omit `self` unless required for disambiguation
- Name booleans with `is`/`has` prefix (e.g., `isRecording`, `hasPermission`)
- Name unused closure parameters with `_`
- Use shorthand syntax: `String?` not `Optional<String>`, `[String]` not `Array<String>`
- Prefer guard clauses for early returns and validation

### Architecture Patterns
- **Native-first architecture**: Deep system integration over hacks
- **No clipboard injection**: Use Accessibility APIs for text insertion
- **No keyboard simulation**: Programmatic text insertion only
- **Model agnostic**: Abstract inference backend behind a common protocol
- Use `NSPanel` with non-activating style to avoid stealing focus

### Testing Strategy
- **Unit Tests**: XCTest for core logic (transcription protocols, audio processing, text insertion)
- **Focus Areas**:
  - Inference backend protocol conformance
  - Audio buffer handling and VAD logic
  - Accessibility API wrappers (mock AXUIElement responses)
- **Integration Tests**: Test end-to-end flows with mock audio data
- Skip UI tests initially (SwiftUI + NSPanel is hard to test, focus on logic)

### Git Workflow
- **Branching**: Feature branches off `main` (e.g., `feat/cloud-inference`, `fix/caret-position`)
- **Commits**: Conventional commits format:
  - `feat:` new features
  - `fix:` bug fixes
  - `refactor:` code changes that neither fix bugs nor add features
  - `docs:` documentation only
  - `test:` adding/updating tests
- **PRs**: Squash merge to main, descriptive PR titles
- **No direct commits to main**

## Domain Context
- **Accessibility API**: Used to read `kAXSelectedTextRangeAttribute` (caret position) and write to `kAXSelectedTextAttribute` (text insertion)
- **AXUIElement**: Core type for querying UI element properties and screen coordinates
- **NSPanel**: AppKit panel type that can float without activating/stealing focus
- **whisper.cpp**: C++ implementation of OpenAI's Whisper model for local speech-to-text
- **VAD (Voice Activity Detection)**: Real-time detection of speech in audio stream

## Important Constraints
- Requires **Accessibility** permissions to function (system prompt on first launch)
- macOS 14.0+ only (uses modern SwiftUI and Swift concurrency APIs)
- Must never steal focus from the active application
- Must preserve clipboard history and undo stacks (no clipboard injection)
- Audio capture must be low-latency for good UX

## External Dependencies
- **whisper.cpp**: Local inference engine (bundled)
- **OpenAI-compatible APIs**: Cloud inference (Groq, OpenAI, Anyscale)
  - Requires user-provided API keys
  - Uses streaming responses for real-time transcription feedback
