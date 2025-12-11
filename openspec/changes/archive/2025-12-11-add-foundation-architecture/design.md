# Design: Foundation Architecture

## Context

Open Dictate is a native macOS dictation app that must replicate the behavior of Apple's built-in dictation:
- Float a HUD at the text cursor without stealing focus
- Insert text directly into the focused application
- Run as a background agent (no Dock icon, no Cmd+Tab entry)

This requires deep system integration via Accessibility APIs and careful window management.

## Goals / Non-Goals

**Goals:**
- Establish project structure that supports non-sandboxed execution
- Implement permission management for Accessibility and Microphone
- Create a "ghost" window that floats without activating
- Detect text caret position across all applications
- Provide menu bar presence for app control

**Non-Goals:**
- Audio recording (Phase 2)
- Transcription services (Phase 2)
- Text insertion (Phase 2)
- Settings UI (Phase 3)
- Hotkey management (Phase 2)

## Decisions

### Decision 1: Non-Sandboxed App

**What:** Remove App Sandbox entitlement from the Xcode project.

**Why:** Sandboxed apps cannot use `AXUIElement` APIs required for:
- Reading focused element attributes
- Detecting caret position via `kAXSelectedTextRangeAttribute`
- Future text insertion via `kAXValueAttribute`

**Alternatives considered:**
- Keep sandbox with temporary exceptions: Not possible—AX APIs are fundamentally incompatible with sandbox
- Use XPC helper: Adds complexity; the helper would still need to be non-sandboxed

### Decision 2: NSPanel with .nonactivatingPanel Style

**What:** Use `NSPanel` subclass with `styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow]`.

**Why:** This is the only way to create a window that:
- Floats above other windows (`level = .floating`)
- Does not steal focus when clicked (`canBecomeKey = false`)
- Appears on all Spaces (`.canJoinAllSpaces`)
- Works in fullscreen apps (`.fullScreenAuxiliary`)

**Reference implementations:**
- VoiceInk `MiniRecorderPanel`
- AeroSpace `NSPanelHud`
- Maccy `FloatingPanel`
- CopilotForXcode `OverlayPanel`

### Decision 3: AXUIElement for Caret Detection

**What:** Use `AXUIElementCreateSystemWide()` → focused app → focused element → `kAXSelectedTextRangeAttribute` → `kAXBoundsForRangeParameterizedAttribute`.

**Why:** This is the standard macOS approach for getting screen coordinates of text selection/cursor. Used by CopilotForXcode for widget positioning.

**Limitations:**
- Requires Accessibility permission
- Some apps don't expose text range attributes (will fall back to window center)
- Coordinate conversion needed (AX uses top-left origin, AppKit uses bottom-left)

### Decision 4: LSUIElement for Agent App

**What:** Set `LSUIElement = YES` in Info.plist.

**Why:** This makes the app:
- Not appear in Dock
- Not appear in Cmd+Tab app switcher
- Behave like a system service

**Trade-off:** Users must access the app via menu bar only. This matches native dictation behavior.

### Decision 5: Swift Package Manager for Dependencies

**What:** Use SPM via Package.swift instead of CocoaPods/Carthage.

**Why:** 
- Modern Apple-recommended approach
- Simpler dependency management
- All chosen dependencies (KeyboardShortcuts, Settings, Defaults) support SPM

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Non-sandboxed apps may face App Store rejection | Distribute outside App Store (DMG, Homebrew) |
| AX permission prompt may confuse users | Show clear onboarding explaining why it's needed |
| Caret detection fails in some apps | Fall back to mouse cursor position or window center |
| NSPanel behavior varies across macOS versions | Test on macOS 13, 14, 15; use stable API patterns |

## Migration Plan

N/A - This is a greenfield implementation.

## Open Questions

1. Should we support macOS 12 (Monterey) or only 13+ (Ventura)?
   - **Proposed:** macOS 13+ only (matches project.md)

2. Should the overlay panel have a close button or rely on escape key?
   - **Proposed:** Escape key only (matches native dictation)
