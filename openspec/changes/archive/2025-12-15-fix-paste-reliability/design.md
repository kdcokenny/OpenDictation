# Design: Paste Reliability Improvements

## Context
The current `TextInsertionService` uses a "universal paste" strategy (clipboard + Cmd+V simulation) that works in most cases but has intermittent failures where old clipboard content is pasted instead of the transcribed text.

## Root Cause Analysis

After analyzing implementations from OpenSuperWhisper (516 stars), voicetypr (183 stars), AudioWhisper (205 stars), Whispera (111 stars), and tambourine-voice (97 stars), the following issues were identified:

### Issue 1: Wrong CGEventSource State
- **Current**: `.hidSystemState` - only HID device state
- **Industry Standard**: `.combinedSessionState` - combined state of all event sources

The `.hidSystemState` may not properly coordinate with other system events, causing race conditions.

### Issue 2: Missing Clipboard Stabilization Delay
- **Current**: Immediately simulates paste after `setString`
- **Industry Standard**: 50ms delay after setting clipboard before paste

Without a delay, the paste event may fire before the clipboard content is fully committed.

### Issue 3: Async Clipboard Restoration
- **Current**: Uses `DispatchQueue.main.asyncAfter` for restoration
- **Industry Standard**: Synchronous delay (Thread.sleep or blocking wait)

Async restoration means other code can interleave, and the paste completion check is not guaranteed.

### Issue 4: Only Saving String Type
- **Current**: Only saves `.string` pasteboard type
- **Industry Standard**: Save all pasteboard types and data

Users lose non-text clipboard content (images, URLs, files).

### Issue 5: No Concurrency Protection
- **Current**: No protection against concurrent paste operations
- **Industry Standard**: Atomic flag or lock to serialize paste operations

Rapid dictation attempts can race and corrupt clipboard state.

## Decisions

### Decision 1: Use `.combinedSessionState`
```swift
// Before
let source = CGEventSource(stateID: .hidSystemState)

// After
let source = CGEventSource(stateID: .combinedSessionState)
```
All surveyed apps use `.combinedSessionState`. This ensures proper coordination with the combined event state.

### Decision 2: Add Synchronous Delays
```swift
// After setting clipboard
Thread.sleep(forTimeInterval: 0.05)  // 50ms stabilization

// After simulating paste, before checking/restoring
Thread.sleep(forTimeInterval: 0.15)  // 150ms for paste to complete
```
Match timing from voicetypr and tambourine-voice.

### Decision 3: Save All Pasteboard Types
```swift
// Before
let previousString = pasteboard.string(forType: .string)

// After
let types = pasteboard.types ?? []
var savedContents: [NSPasteboard.PasteboardType: Data] = [:]
for type in types {
    if let data = pasteboard.data(forType: type) {
        savedContents[type] = data
    }
}
```
Matches OpenSuperWhisper's comprehensive approach.

### Decision 4: Add Concurrency Flag
```swift
private static var isInserting = false
private static let insertionLock = NSLock()

func insertText(_ text: String) -> Bool {
    insertionLock.lock()
    defer { insertionLock.unlock() }
    
    guard !Self.isInserting else {
        logger.warning("Paste operation already in progress")
        return false
    }
    Self.isInserting = true
    defer { Self.isInserting = false }
    // ... rest of implementation
}
```

### Decision 5: Verify Clipboard Before Paste
```swift
// Set clipboard
pasteboard.setString(text, forType: .string)

// Verify it was set
guard pasteboard.string(forType: .string) == text else {
    logger.error("Clipboard content not set correctly")
    return false
}
```

## Alternatives Considered

### Decision 6: Configure Event Source Suppression
```swift
source.setLocalEventsFilterDuringSuppressionState(
    [.permitLocalMouseEvents, .permitSystemDefinedEvents],
    state: .eventSuppressionStateSuppressionInterval
)
```
This prevents user keyboard input from racing with our simulated paste. Mouse and system events (volume, brightness) are still permitted. This is Apple-quality defensive programming.

### Decision 7: Post Explicit Command Key Events
```swift
// More robust than just setting .maskCommand flag
let cmdKeyCode = CGKeyCode(55)  // Command key
let vKeyCode = CGKeyCode(kVK_ANSI_V)

// Create all events
let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true)
let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false)

// Set Command flag on V events
vDown?.flags = .maskCommand
vUp?.flags = .maskCommand

// Post in sequence
cmdDown?.post(tap: .cghidEventTap)
vDown?.post(tap: .cghidEventTap)
vUp?.post(tap: .cghidEventTap)
cmdUp?.post(tap: .cghidEventTap)
```
OpenSuperWhisper uses this approach. It's more explicit and ensures apps that don't properly recognize the Command flag still receive correct events.

### Decision 8: Keep `.cghidEventTap` for Event Posting
The HID event tap is used by the majority of successful dictation apps (OpenSuperWhisper, Whispera). It's lower-level and simulates hardware input directly. No change needed from current implementation.

## Alternatives Not Implemented

### AppleScript Fallback
voicetypr falls back to AppleScript (`osascript -e "tell application System Events..."`) if CGEvent fails.

**Decision**: Not implementing. CGEvent should be reliable with proper configuration. AppleScript adds complexity, requires Automation permission, and is slower.

### Retry Logic
voicetypr retries paste up to 2 times.

**Decision**: Not implementing. We're fixing root causes (timing, event source state, suppression). Retry masks problems rather than solving them.

### Session Event Tap
AudioWhisper uses `.cgSessionEventTap` instead of `.cghidEventTap`.

**Decision**: Keep `.cghidEventTap`. Industry consensus favors HID tap. Session tap provides no practical benefit for paste simulation.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Synchronous delays add latency | 50ms + 150ms = 200ms added, acceptable for reliability |
| Lock contention if spammed | Lock is brief, only protects clipboard ops |
| Saving all types uses more memory | Temporary, cleared after 150ms |
| Event suppression blocks user input | Only during paste (~50ms), mouse still works |

## Summary of Apple-Quality Hardening

1. **`.combinedSessionState`** - Proper event coordination
2. **50ms clipboard stabilization** - Ensure content is committed
3. **150ms paste completion wait** - Synchronous, guaranteed ordering
4. **Full clipboard preservation** - Save all types, not just string
5. **Concurrency lock** - Prevent overlapping operations
6. **Clipboard verification** - Confirm content before paste
7. **Event source suppression** - Prevent input interference
8. **Explicit Command key events** - Maximum app compatibility
