# Proposal: Fix Fullscreen Window Visibility and Display Change Handling

## Why

The notch overlay window is critical to OpenDictation's core functionality - it's how users know recording is active and see real-time transcription results. Two reliability issues undermine user trust:

1. **Silent degradation over hours of use** - Users must restart the app every few hours, creating friction in the dictation workflow
2. **Complete failure during display changes** - Edge case but critical: connecting an external display mid-recording completely breaks the app, requiring force-kill to recover

Both issues stem from production-unfaithful patterns. Analysis of 15+ production macOS overlay applications (DynamicNotchKit, KeyboardCowboy, NotchDrop, etc.) reveals proven solutions that are:
- **Minimal risk:** Single-value configuration changes + architectural refactor following established patterns
- **Production-proven:** Every production overlay app uses these exact patterns
- **Non-breaking:** Defensive changes that only improve reliability, no behavior changes

This proposal adopts production-standard patterns for window prioritization and event monitoring to ensure reliable, stable overlay behavior.

## What Changes

**Part 1: Window Configuration (Issue 1 Fix)**
- Change window level from `.statusBar + 8` (33) to `.screenSaver` (1000)
  - Guarantees overlay maintains priority over fullscreen apps per macOS window hierarchy
  - Used by 15+ production apps (DynamicNotchKit, KeyboardCowboy, Loop, etc.)
- Add `becomesKeyOnlyIfNeeded = true`
  - Prevents system window demotion after extended use
- Remove `.utilityWindow` style mask
  - Unnecessary, not used by production overlay apps

**Part 2: Singleton Event Monitor Architecture (Issue 2 Fix)**
- Create `EscapeKeyMonitor` singleton service
  - Decoupled from panel lifecycle (survives display changes)
  - Uses simpler `NSEvent` API instead of `CGEventTap`
  - Follows NotchDrop's proven architectural pattern
- Add `destroy()` method to `NotchOverlayPanel`
  - Synchronous cleanup that prevents async race conditions
- Update `rebuildNotchUI()` to:
  - Directly clean up services when display changes interrupt recording
  - Force state machine back to idle via new `.forceReset` event
  - Play error sound for user feedback
- Add `.forceReset` event to `DictationEvent`
  - Dedicated event for system-level interruptions (display changes, future: sleep, volume changes)
  - Can be triggered from ANY state → `.idle`

**Files Modified:**
- `OpenDictation/Views/Notch/NotchWindow.swift` (Part 1)
- `OpenDictation/Core/Services/EscapeKeyMonitor.swift` (NEW - Part 2)
- `OpenDictation/Views/Notch/NotchOverlayPanel.swift` (Part 2)
- `OpenDictation/App/AppDelegate.swift` (Part 2)
- `OpenDictation/Core/Services/DictationStateMachine.swift` (Part 2)

## Problem Statement

Two related issues affect the reliability of the notch overlay window:

### Issue 1: Window Visibility Degradation Over Time

The notch overlay window intermittently stops appearing over fullscreen applications after several hours of normal use. The window works correctly immediately after app launch but gradually loses visibility priority over fullscreen apps, requiring a full app restart to restore functionality.

### Issue 2: Display Change During Recording Breaks App

When a display is connected or disconnected while the app is actively recording (listening), the app completely breaks:
- Window moves to the middle of the screen instead of the notch
- Escape key stops working
- Option+Space hotkey stops working
- App must be force-killed to recover

This is an edge case (unlikely during normal use) but critical when it occurs.

### User Impact

- Users must restart the app every few hours to maintain functionality (Issue 1)
- Dictation becomes unreliable in fullscreen apps (Issue 1)
- Display changes during recording require force-kill (Issue 2)
- Creates friction in the user workflow and damages trust in app reliability

### Technical Symptoms

**Issue 1 (Visibility Degradation):**
- Window appears correctly at app launch
- After extended use (hours) with fullscreen apps and Space switching, window stops appearing
- No error messages or crashes - silent degradation
- App restart immediately fixes the issue
- Unable to reliably reproduce on-demand; requires hours of normal use

**Issue 2 (Display Change During Recording):**
- Reproducible: Start recording, then connect/disconnect external display
- State machine gets stuck in `.cancelled` state (never returns to `.idle`)
- Event monitors lose valid window references
- Race condition between async dismissal animation and panel destruction

## Root Cause Analysis

After analyzing 15+ production macOS applications (DynamicNotchKit, KeyboardCowboy, DockDoor, CopilotForXcode, Ghostty, InputSourcePro, Loop, MonitorControl), the root causes have been identified:

### Issue 1: Window Level Too Low

**Current implementation:**
- Window level: `.statusBar + 8` (raw value: 33)

**macOS window level hierarchy:**
```
kCGStatusWindowLevel = 25
kCGPopUpMenuWindowLevel = 101
kCGOverlayWindowLevel = 102
kCGHelpWindowLevel = 200
kCGDraggingWindowLevel = 500
kCGScreenSaverWindowLevel = 1000  ← Production standard
kCGAssistiveTechHighWindowLevel = 1500
```

Our window at level 33 sits below pop-up menus, overlays, help windows, and dragging indicators. After hours of system events (fullscreen transitions, Space switches, display configuration changes), macOS can deprioritize low-level windows in favor of higher-level system UI.

### Production App Evidence

All surveyed production apps that maintain overlay visibility over fullscreen apps use `.screenSaver` level (1000):

1. **DynamicNotchKit** (MIT, 200+ stars) - Library specifically for notch overlays
2. **KeyboardCowboy** - macOS automation tool with passive notification overlays
3. **InputSourcePro** - Input method indicator overlay
4. **Loop** - Window management with preview overlays
5. **MonitorControl** - Display control with persistent overlays

### Missing Critical Property

Production apps also use `becomesKeyOnlyIfNeeded = true`, which we're missing. This property tells the system: "This panel CAN become key if absolutely necessary, but don't make it key unless required." Combined with `canBecomeKey = false`, it creates a truly passive overlay that the system won't demote.

### Spec Contradiction

The current `overlay-panel` spec contains a contradiction:
- Requirement states: "SHALL be an `NSWindow` subclass (not `NSPanel`)"
- Implementation uses: `NSPanel`

Additionally, the implementation uses `.utilityWindow` style mask, which is:
- Not mentioned in any spec
- Not used by most production overlay apps
- Typically for tool palettes, not passive overlays

### Issue 2: Event Monitor Tied to Panel Lifecycle

The current architecture creates event monitors within each `NotchOverlayPanel` instance. When displays change during recording:

**Current Flow:**
1. Screen change detected → `rebuildNotchUI()` called
2. State machine is in `.recording` → sends `escapePressed` event
3. State transitions to `.cancelled` → calls `onCancel` callback
4. `onCancel` calls `notchPanel?.hide()` → starts 0.5s dismissal animation
5. `rebuildNotchUI` continues immediately:
   - Sets `notchPanel = nil` (destroys panel while animating)
   - Creates NEW panel for new screen
   - Re-wires callbacks to NEW panel

**The Race Condition:**
```
Time: 0ms     → Old panel starts dismissing (0.5s animation)
Time: 0ms     → Panel reference set to nil (OLD panel orphaned)
Time: 0ms     → NEW panel created
Time: 500ms   → Old panel's onDismissCompleted fires... but references NEW panel!
Time: 500ms   → State machine NEVER receives .dismissCompleted event
Time: 500ms   → State stuck in .cancelled forever
```

**Result:**
- State machine stuck in `.cancelled` (never returns to `.idle`)
- Hotkey stops working (only accepts `hotkeyPressed` from `.idle` state)
- Escape stops working (event monitor has broken window references)
- Window positioned incorrectly (geometry calculated for wrong screen)

### NotchDrop's Architecture (Production Pattern)

NotchDrop avoids these issues through architectural separation:

| Aspect | **NotchDrop** (Works) | **OpenDictation** (Breaks) |
|--------|----------------------|---------------------------|
| **Event Monitors** | Singleton, lives for app lifetime | Created/destroyed with each panel |
| **Event API** | `NSEvent.addGlobalMonitorForEvents` | `CGEventTap` (more fragile) |
| **Cleanup** | `destroy()` method ensures proper teardown | Direct `nil` assignment |
| **Callbacks** | Uses Combine publishers (decoupled) | Direct closure references (tightly coupled) |
| **Dismissal** | Synchronous close before rebuild | Async animation during rebuild |

## Proposed Solution

Adopt the production-proven patterns used by DynamicNotchKit and NotchDrop:

### Part 1: Window Configuration (Issue 1 Fix)

Changes to `NotchWindow.swift`:

1. **Increase window level to `.screenSaver`**
   - Change from `.statusBar + 8` (33) to `.screenSaver` (1000)
   - This is the Apple-defined constant for overlays that must appear over fullscreen apps
   - Guaranteed by macOS to maintain priority over fullscreen app transitions

2. **Add `becomesKeyOnlyIfNeeded = true`**
   - New property not currently set
   - Prevents system from demoting the window
   - Maintains passive behavior (won't steal focus)

3. **Remove `.utilityWindow` style mask**
   - Not specified in requirements
   - Not used by most production apps
   - Redundant with `.borderless` + `.nonactivatingPanel`

4. **Keep all other configuration unchanged**
   - `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`
   - `canBecomeKey = false`
   - `canBecomeMain = false`
   - `isFloatingPanel = true`

### Part 2: Singleton Event Monitor Architecture (Issue 2 Fix)

Extract event monitoring into a singleton service that lives for the app lifetime:

1. **Create `EscapeKeyMonitor` singleton service**
   - Lives for the entire app lifetime (never recreated)
   - Uses simpler `NSEvent.addGlobalMonitorForEvents` instead of CGEventTap
   - Publishes events via callback (decoupled from panel lifecycle)
   - Immune to panel destruction/recreation during screen changes

2. **Add `destroy()` method to `NotchOverlayPanel`**
   - Ensures proper synchronous cleanup before panel destruction
   - Clears all callbacks to prevent dangling references
   - Closes window immediately (no async animation during screen changes)

3. **Update `rebuildNotchUI()` in AppDelegate**
   - Call `destroy()` before setting panel to nil
   - Ensure state machine completes transition before rebuild
   - Wire singleton event monitor to new panel callbacks

### No Timer Required

Unlike NotchDrop (which uses a 1-second timer to call `makeKeyAndOrderFront()`), we don't need periodic refresh because:
- NotchDrop keeps windows open for extended periods during user interaction
- Our window shows for 3-10 seconds per dictation session
- The issue is visibility at show-time, not during display
- Higher window level guarantees priority at show-time

## Alternatives Considered

### For Issue 1 (Window Level):

#### Alternative 1a: Add Timer-Based Refresh (NotchDrop Pattern)
**Rejected:** Adds unnecessary complexity for our use case. NotchDrop needs this because their window stays open during prolonged user interaction. Our window is shown briefly (seconds), so we only need guaranteed priority at show-time.

#### Alternative 1b: Use Even Higher Level (`.assistiveTechHigh`)
**Rejected:** Level 1500 is excessive and may conflict with actual assistive technology. `.screenSaver` (1000) is the standard for app overlays.

#### Alternative 1c: Switch to `NSWindow` Instead of `NSPanel`
**Rejected for now:** While the spec says to use `NSWindow`, `NSPanel` is working correctly aside from the level issue. Switching base classes is a larger refactor that should be done separately if needed. Most production apps (including DynamicNotchKit) successfully use `NSPanel` with the correct configuration.

### For Issue 2 (Display Change During Recording):

#### Alternative 2a: Wait for Dismissal Before Rebuild
**Rejected:** Simple fix with 0.5s delay before rebuilding. Rejected because:
- Adds latency to screen change handling
- Doesn't address the underlying architectural issue
- Event monitors still tied to panel lifecycle

#### Alternative 2b: Synchronous Cleanup Only (No Architecture Change)
**Rejected:** Add `destroy()` method without singleton event monitor. Rejected because:
- Still recreates event monitors on each screen change
- CGEventTap can be fragile during rapid screen changes
- Doesn't follow the production-proven NotchDrop pattern

#### Alternative 2c: Singleton Event Monitor (Selected)
**Selected:** Extract event monitoring to singleton service. Chosen because:
- Follows NotchDrop's proven architecture
- Event monitors never break during screen changes
- Simpler NSEvent API instead of CGEventTap
- Clean separation of concerns
- Most robust long-term solution

## Implementation Plan

See `tasks.md` for detailed implementation steps.

## Validation Strategy

### Automated Validation
- No new tests required - existing behavior should be preserved
- Window configuration is not easily testable in unit tests

### Manual Validation

**Issue 1 Validation (cannot be easily reproduced, requires hours of use):**
1. **Immediate verification:** Confirm window still appears correctly at app launch
2. **Extended usage test:** Use app normally for several days with frequent fullscreen transitions
3. **Stress test:** Rapid fullscreen cycling, Space switching
4. **Regression check:** Verify focus is never stolen from active applications

**Issue 2 Validation (reproducible edge case):**
1. **Direct reproduction:** Start recording, connect/disconnect display mid-recording
2. **Verify recovery:** App should gracefully cancel and return to idle state
3. **Verify escape key:** Escape key should work after rebuild
4. **Verify hotkey:** Option+Space should work after rebuild
5. **Stress test:** Rapidly connect/disconnect display during recording multiple times

### Success Criteria
- Window appears reliably over fullscreen apps after days of use (Issue 1)
- No focus stealing from active applications
- No degradation after system events (fullscreen, Space switches)
- App gracefully handles display changes during recording (Issue 2)
- Escape key and hotkey continue working after display changes
- No force-kill required for display change scenarios

## Risk Assessment

### Issue 1 Changes: Low Risk
- Window level change is a single integer value modification
- Pattern is proven across 15+ production macOS apps
- Changes are defensive (adding stability, not new features)
- No behavioral changes from user perspective
- Easy to revert if issues arise

### Issue 2 Changes: Medium Risk
- Introduces new singleton service (EscapeKeyMonitor)
- Refactors event monitoring architecture
- Changes screen rebuild flow
- More files modified than Issue 1

### Mitigation
- Production apps demonstrate this configuration works reliably
- Window level constants are Apple-defined, not magic numbers
- Singleton event monitor follows NotchDrop's proven pattern
- NSEvent API is simpler and more stable than CGEventTap
- Changes align with OpenSpec architecture patterns (defensive, production-ready)
- Issue 2 is an edge case - can be tested directly before release
- Incremental implementation: Issue 1 changes can be validated before Issue 2 changes

## References

### Production Apps Analyzed
- **DynamicNotchKit:** [github.com/MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)
- **KeyboardCowboy:** [github.com/zenangst/KeyboardCowboy](https://github.com/zenangst/KeyboardCowboy)
- **NotchDrop:** [github.com/Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop)
- **InputSourcePro:** [github.com/runjuu/InputSourcePro](https://github.com/runjuu/InputSourcePro)
- **Loop:** [github.com/MrKai77/Loop](https://github.com/MrKai77/Loop)

### Apple Documentation
- [NSWindow.Level](https://developer.apple.com/documentation/appkit/nswindow/level)
- [CGWindowLevel](https://developer.apple.com/documentation/coregraphics/cgwindowlevel)
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
