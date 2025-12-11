# Change: Add Foundation Architecture

## Why

Open Dictation requires a native macOS architecture that can display a floating HUD at the text caret, record audio, and insert transcribed text—all without stealing focus from the active application. This foundation must be established before any transcription or recording features can be built.

## What Changes

- **NEW** Xcode project configuration with non-sandboxed entitlements
- **NEW** Permissions capability for Accessibility and Microphone authorization
- **NEW** Overlay panel capability using NSPanel with non-activating behavior
- **NEW** Accessibility service capability for caret position detection via AXUIElement
- **NEW** Menu bar capability for app lifecycle and user interaction

## Impact

- Affected specs: `permissions`, `overlay-panel`, `accessibility`, `menu-bar` (all new)
- Affected code: Creates entire `OpenDictation/` source tree
- Dependencies: sindresorhus/KeyboardShortcuts, sindresorhus/Settings, sindresorhus/Defaults
