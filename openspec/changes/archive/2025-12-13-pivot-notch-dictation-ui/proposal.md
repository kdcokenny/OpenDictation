# Change: Replace floating pill with notch-based dictation UI

## Why

The current floating pill UI at the bottom of the screen doesn't feel native to modern MacBook hardware. MacBooks with a notch (2021+) have an opportunity to integrate the dictation UI directly into the notch area, similar to Apple's Dynamic Island on iPhone. This creates a more premium, hardware-integrated experience.

The current approach used by projects like Boring Notch requires private APIs. However, NotchDrop demonstrates a workaround using a borderless window overlay that achieves the same visual effect without private APIs, making it App Store safe.

## What Changes

- **BREAKING**: Remove the floating pill UI at bottom-center of screen
- **BREAKING**: Non-notch Macs will have no visual UI (audio feedback only)
- Add notch-aware dictation panel that expands horizontally from the hardware notch
- Implement Dynamic Island-style expand/collapse animations
- Replace waveform with dual-element layout: recording icon (left) + waveform bars (right)
- Add SF Symbol effects for state indication (`.pulse.byLayer` for recording, `.breathe` for processing)
- Add Siri-like idle breathing animation to waveform when user is not speaking

## Impact

- Affected specs: `dictation-ui`, `overlay-panel`
- Affected code:
  - `DictationOverlayPanel.swift` - Major rewrite to `NotchOverlayPanel`
  - `DictationHUDView.swift` - Replaced with `NotchDictationView`
  - `WaveformView.swift` - Enhanced with breathing animation
  - `AppDelegate.swift` - Wire up new panel
  - New files: `NSScreen+Notch.swift`, `NotchShape.swift`
- Hardware requirement: MacBook with notch (2021 MacBook Pro, 2022+ MacBook Air)
- Users on non-notch Macs should file an issue if they want UI support added
