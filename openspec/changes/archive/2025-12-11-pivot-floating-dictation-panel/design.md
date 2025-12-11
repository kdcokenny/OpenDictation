# Design: Floating Dictation Panel

## Context

The original design attempted to replicate macOS native dictation's caret-following HUD. After research, we've determined this approach has limitations (can't stream text in real-time, caret detection is complex/fragile).

We're pivoting to a **fixed-position floating panel** at the bottom-center of the screen—a pattern proven by Wispr Flow and similar utilities. This is simpler, more reliable, and still feels native when executed well.

## Goals / Non-Goals

**Goals:**
- Floating pill panel at bottom-center using macOS 26 Liquid Glass
- Waveform visualization during recording (5 bars)
- Sine wave animation during processing (only if >0.5s)
- Native-feeling animations (spring for appear, fade+scale for dismiss)
- Audio feedback (start/end sounds, volume ducking)
- Detect text field → auto-paste; no text field → clipboard only
- Toggle activation via configurable hotkey (default: Option+Space)

**Non-Goals:**
- Caret-following positioning (removed)
- Separate caret overlay (removed)
- Real-time text streaming (API limitation)
- Toast notifications (not Mac-native)

## Decisions

### Decision 1: Fixed Bottom-Center Positioning

**What:** Panel appears at fixed position (bottom-center, ~60px from bottom edge) instead of following text caret.

**Why:**
- Simpler implementation, no cursor tracking needed
- Works reliably in all apps (even those with poor accessibility)
- Proven pattern (Wispr Flow uses this approach)
- Visible without obscuring user's work

**Trade-off:** Less contextual than caret-following, but more reliable and simpler.

### Decision 2: macOS 26 Liquid Glass Material

**What:** Use `NSGlassEffectView` with `.regular` style (or SwiftUI `.glassEffect()`) for panel background.

**Why:**
- Native macOS 26 design language
- Automatic adaptation to light/dark mode and desktop
- Feels built-in to the OS

**Implementation:**
```swift
// AppKit approach
let glassView = NSGlassEffectView()
glassView.style = .regular
glassView.cornerRadius = panelHeight / 2  // Full capsule

// SwiftUI approach
content.glassEffect()
```

### Decision 3: 5-Bar Waveform Visualization

**What:** Display 5 vertical bars that respond to audio levels during recording.

**Design:**
- Bar width: ~4px
- Bar spacing: ~6px
- Bar height: 8px (min) to 28px (max), driven by audio level
- Bar color: Primary label color (adapts to appearance)
- Corner radius: 2px per bar
- Total panel size: ~120×44px

**Why:**
- Compact, fits small pill panel
- Clear visual feedback that audio is being captured
- 5 bars is enough resolution without being busy

### Decision 4: Processing Animation (Sine Wave)

**What:** During transcription, bars animate in a sine wave pattern (phase offset per bar).

**Why:**
- Indicates "working" without demanding attention
- Smooth, continuous animation feels polished
- Distinct from recording state (which responds to audio)

**Optimization:** Only show if processing takes >0.5s. Fast transcriptions skip directly to success dismiss.

### Decision 5: Panel Animations

**Appear:**
- Fade in (0→1) + scale up (0.95→1.0)
- `spring(duration: 0.3, bounce: 0.15)`

**Dismiss (success/cancel):**
- Fade out + scale down (1.0→0.95)
- `spring(duration: 0.2, bounce: 0)` (no bounce—quick exit)

**Dismiss (empty result):**
- Horizontal shake (3 cycles, ±8px) → fade out
- Mac-native "nope" signal (like login window)
- No sound (absence of success sound communicates)

**Dismiss (error):**
- Show error icon (`exclamationmark.triangle.fill`) with primary color (no red tint—icons are all white/primary for consistency)
- Trigger shake animation (same as empty)
- Play `NSSound.beep()` (system rejection sound)
- Hold for 0.5s → fade out

**Result state icons (all use primary/white color):**
- success: `checkmark`
- copiedToClipboard: `doc.on.clipboard`
- error: `exclamationmark.triangle.fill`
- empty: `waveform.slash`

**Why these choices:**
- Spring appear with slight bounce feels alive
- Quick dismiss without bounce keeps utility app snappy
- Shake is the established Mac "rejection" pattern (used for both error and empty)
- All icons primary color for visual consistency; sound differentiates error from empty
- Brief error visibility doesn't demand interaction

### Decision 6: Text Field Detection with Graceful Fallback

**What:** Detect if user is in a text field before auto-pasting. If not (or if detection fails), copy to clipboard only.

**Detection order:**
1. `AXRole` ∈ {AXTextField, AXTextArea, AXSearchField, AXComboBox, AXSecureTextField}
2. `AXSubrole` ∈ {AXSearchField, AXSecureTextField, AXTextInput}
3. `AXEditable` == true
4. `AXActions` contains "AXInsertText" or "AXDelete"

**Graceful fallback:** If Accessibility API fails entirely (permission denied, app doesn't support it), default to clipboard-only. Never error out—fail toward the safer behavior.

**Why:**
- Prevents pasting into unexpected places
- ~90-95% reliable across common Mac apps
- Clipboard-only is safe fallback—user can Cmd+V when ready

### Decision 7: Configurable Hotkey via Settings

**What:** Default Option+Space, customizable via Settings UI using KeyboardShortcuts library.

**Why:**
- KeyboardShortcuts library provides native-feeling hotkey recorder
- Option+Space is a good default, unlikely to conflict
- Users can customize if needed

### Decision 8: Show Clipboard Icon When Not in Text Field

**What:** When transcription succeeds but user is not in a text field, show `doc.on.clipboard` icon before dismiss (instead of checkmark).

**Why:**
- Provides clear feedback that text went to clipboard only (no paste)
- Differentiates "inserted" (checkmark) from "clipboard only" (clipboard icon)
- Minimal added complexity—just another HUDVisualState case
- Prevents confusion about where text went

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Liquid Glass not available on older macOS | Require macOS 26+ (already our target) |
| Audio level mapping looks wrong | Tune with logarithmic scaling; iterate |
| Detection fails in some apps | Graceful fallback to clipboard-only |
| Processing takes >10s | Let sine wave run; Escape still works to cancel |
| Panel obscures content at bottom of screen | 60px margin; most content is above this |

## Open Questions

None—all resolved during planning.
