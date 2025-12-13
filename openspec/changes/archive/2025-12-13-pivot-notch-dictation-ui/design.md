# Design: Notch-Based Dictation UI

## Context

The MacBook notch (introduced 2021) provides a unique opportunity for native-feeling UI integration. Projects like Boring Notch have popularized this pattern but rely on private APIs (`CGSSetWindowBackgroundBlurRadius`, etc.). NotchDrop demonstrates a pure public API approach using borderless windows.

### Stakeholders
- End users with notch MacBooks (2021+)
- End users without notch (older MacBooks, external displays) - explicitly unsupported initially

### Constraints
- Must not use private APIs (App Store compatibility)
- Must not steal focus from active application
- Must work with fullscreen apps and across Spaces
- Audio feedback must continue working as-is

## Goals / Non-Goals

### Goals
- Create a Dynamic Island-style UI that expands from the hardware notch
- Horizontal expansion only (left and right from notch edges)
- Native macOS feel with SF Symbol effects
- Smooth spring animations matching system behavior
- Audio-reactive waveform (jagged bars like Boring Notch music player)

### Non-Goals
- Support for non-notch Macs (document and defer to user requests)
- Vertical dropdown expansion (keep it minimal/compact)
- Click interactions within the notch UI
- Music player or other non-dictation features

## Source Code References

We use two reference implementations:
- **NotchDrop** (MIT License) - Infrastructure: window management, mask with "ears", alignment
- **Boring Notch** (GPL-3.0) - Design: corner radii, waveform bar dimensions, visual styling

| Purpose | Repository | License | Key Files |
|---------|-----------|---------|-----------|
| Infrastructure | `Lakr233/NotchDrop` | MIT | `NotchView.swift`, `NotchViewModel.swift`, `Ext+NSScreen.swift` |
| Design/Styling | `TheBoredTeam/boring.notch` | GPL-3.0 | `NotchShape.swift`, `MusicVisualizer.swift`, `matters.swift` |

## Decisions

### Decision: Use NotchDrop's overlay technique
**What**: Create a borderless, full-screen-width window at the top of the screen with `.statusBar + 8` window level.

**Why**: This is the only known public API approach that works reliably without private APIs. The window covers the menu bar area, and we draw our own notch shape on top of it.

**Source**: `Lakr233/NotchDrop/NotchDrop/NotchWindowController.swift`

**Alternatives considered**:
- Private API approach (Boring Notch) - Rejected: Not App Store safe
- Regular floating panel - Rejected: Cannot overlay the notch area

### Decision: Use Boring Notch's corner radii
**What**: Use `topCornerRadius: 6, bottomCornerRadius: 14` for the notch shape.

**Why**: Boring Notch's corner radii look more polished and match the hardware notch better than NotchDrop's simpler rounded rectangles.

**Source**: `TheBoredTeam/boring.notch/boringNotch/sizing/matters.swift` line 18
```swift
let cornerRadiusInsets = (
    opened: (top: 19, bottom: 24),
    closed: (top: 6, bottom: 14)
)
```

### Decision: Use NotchDrop's mask with "ears" effect
**What**: Apply a mask using `blendMode(.destinationOut)` to create curved cutouts at the top corners that make content appear to emerge from the notch.

**Why**: This creates the visual illusion that the UI is extending from the hardware notch rather than being a separate box below it.

**Source**: `Lakr233/NotchDrop/NotchDrop/NotchView.swift` lines 82-127 (`notchBackgroundMaskGroup`)

### Decision: Use Boring Notch's waveform bar dimensions
**What**: 4 bars, 2px width, 2px spacing, 14px total height, random heights between 0.35-1.0.

**Why**: Matches the polished look of Boring Notch's music visualizer.

**Source**: `TheBoredTeam/boring.notch/boringNotch/components/Music/MusicVisualizer.swift` lines 28-35
```swift
let barWidth: CGFloat = 2
let barCount = 4
let spacing: CGFloat = barWidth  // = 2
let totalHeight: CGFloat = 14
```

### Decision: Audio-reactive waveform with smooth transitions
**What**: Waveform behavior varies based on audio input level:
- **Idle** (audioLevel < 0.15): Subtle random movement, range 0.25-0.45, slower updates (~0.4s)
- **Active** (audioLevel >= 0.15): Responsive random bars scaled by audioLevel, faster updates (~0.2s)

**Why**: Creates a natural transition between silent (breathing) and speaking (reactive) states.

**Implementation**:
```swift
// Smooth blend between idle and active ranges based on audioLevel
let idleMax: CGFloat = 0.45
let activeMax: CGFloat = min(1.0, 0.4 + CGFloat(audioLevel) * 0.8)
let blendFactor = CGFloat(min(1, audioLevel / 0.3))
let blendedMax = idleMax + (activeMax - idleMax) * blendFactor
let targetScale = CGFloat.random(in: 0.35 ... blendedMax)
```

### Decision: 100ms render delay
**What**: Add `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` before rendering content after window creation.

**Why**: NotchDrop discovered this is required to avoid rendering glitches. Without it, the window content may not render correctly on first display.

### Decision: Horizontal-only expansion
**What**: The expanded state only extends left and right from the notch edges, staying at the notch's vertical height (~37px on most models).

**Why**: Keeps the UI minimal and less intrusive. The dictation UI only needs to show a small icon and waveform, not a full panel.

### Decision: No UI for non-notch Macs
**What**: If `NSScreen.safeAreaInsets.top == 0`, do not show any visual UI.

**Why**: 
- Simplifies initial implementation
- The floating pill approach is being deprecated
- Users who need UI can file an issue, allowing demand-driven prioritization

### Decision: Processing state keeps waveform visible
**What**: During processing/transcription, the waveform remains visible on the right side with low idle activity, rather than being replaced with an icon.

**Why**: Provides visual continuity and indicates the system is still "listening" even though it's processing.

### Decision: Black background with white icons
**What**: Solid black background (matching notch hardware) with white/primary-colored SF Symbols.

**Why**: Creates visual continuity with the hardware notch. The black background makes the expanded area appear as a natural extension of the notch.

## Technical Implementation

### Window Configuration (from NotchDrop)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchWindowController.swift`
```swift
// NotchWindow.swift
styleMask: [.borderless, .fullSizeContentView]
level = .statusBar + 8
backgroundColor = .clear
isOpaque = false
hasShadow = false
collectionBehavior = [
    .fullScreenAuxiliary,
    .stationary,
    .canJoinAllSpaces,
    .ignoresCycle
]
```

### Notch Detection (from NotchDrop)
**Source**: `Lakr233/NotchDrop/NotchDrop/Ext+NSScreen.swift`
```swift
// NSScreen+Notch.swift
extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        // NotchDrop adds this extra guard:
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        let notchWidth = frame.width - leftPadding - rightPadding
        return CGSize(width: notchWidth, height: notchHeight)
    }
    
    var hasNotch: Bool { notchSize != .zero }
}
```

### NotchShape (from Boring Notch)
**Source**: `TheBoredTeam/boring.notch/boringNotch/components/Notch/NotchShape.swift`
```swift
struct NotchShape: Shape {
    private var topCornerRadius: CGFloat = 6
    private var bottomCornerRadius: CGFloat = 14
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Uses quadCurve for smooth notch-like corners
        // Full implementation from NotchShape.swift lines 37-104
    }
}
```

### Mask with "Ears" Effect (from NotchDrop)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchView.swift` lines 82-127
```swift
var notchBackgroundMaskGroup: some View {
    Rectangle()
        .foregroundStyle(.black)
        .frame(width: notchSize.width, height: notchSize.height)
        .clipShape(.rect(
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius
        ))
        // LEFT EAR - curved cutout at top-left
        .overlay {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .frame(width: cornerRadius, height: cornerRadius)
                    .foregroundStyle(.black)
                Rectangle()
                    .clipShape(.rect(topTrailingRadius: cornerRadius))
                    .foregroundStyle(.white)
                    .frame(width: cornerRadius + spacing, height: cornerRadius + spacing)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: -cornerRadius - spacing + 0.5, y: -0.5)
        }
        // RIGHT EAR - curved cutout at top-right (mirrored)
        .overlay {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .frame(width: cornerRadius, height: cornerRadius)
                    .foregroundStyle(.black)
                Rectangle()
                    .clipShape(.rect(topLeadingRadius: cornerRadius))
                    .foregroundStyle(.white)
                    .frame(width: cornerRadius + spacing, height: cornerRadius + spacing)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: cornerRadius + spacing - 0.5, y: -0.5)
        }
}
```

### View Alignment (from NotchDrop)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchView.swift` lines 42-67
```swift
var body: some View {
    ZStack(alignment: .top) {  // Align content to top
        notch
            .zIndex(0)
        // content...
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)  // Anchor to top
}
```

### Animation System (from NotchDrop)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchViewModel.swift` line 21
```swift
let animation: Animation = .interactiveSpring(
    duration: 0.5,
    extraBounce: 0.25,
    blendDuration: 0.125
)
```

### Waveform Bars (from Boring Notch)
**Source**: `TheBoredTeam/boring.notch/boringNotch/components/Music/MusicVisualizer.swift`
```swift
// Bar setup (lines 28-35)
let barWidth: CGFloat = 2
let barCount = 4
let spacing: CGFloat = barWidth  // = 2
let totalHeight: CGFloat = 14

// Random animation (lines 64-80)
let targetScale = CGFloat.random(in: 0.35 ... 1.0)
let animation = CABasicAnimation(keyPath: "transform.scale.y")
animation.duration = 0.3

// Update interval (line 56)
Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true)
```

### Spacing Value (from NotchDrop)
**Source**: `Lakr233/NotchDrop/NotchDrop/NotchViewModel.swift` line 66
```swift
@Published var spacing: CGFloat = 16
```

### SF Symbol Effects
```swift
// Recording state - left icon
Image(systemName: "record.circle.fill")
    .foregroundStyle(.white)
    .symbolEffect(.pulse.byLayer, options: .repeat(.continuous), isActive: isRecording)

// Processing state - left icon only (waveform stays on right)
Image(systemName: "circle.fill")
    .foregroundStyle(.white)
    .symbolEffect(.breathe, options: .repeat(.continuous), isActive: isProcessing)

// Error state
Image(systemName: "xmark.circle.fill")
    .foregroundStyle(.white)

// Empty state
Image(systemName: "circle")
    .foregroundStyle(.white)
```

### View Layout (Expanded State)
```
┌────────────────────────────────────────────────────────────────────────┐
│ [Recording Icon]    ████████ HARDWARE NOTCH ████████    [Waveform]     │
│  record.circle.fill            ~180px                   4 bars         │
└────────────────────────────────────────────────────────────────────────┘
       ~60px                                                   ~60px
```

## Risks / Trade-offs

### Risk: macOS updates break overlay behavior
- **Mitigation**: Window level and collection behavior are stable public APIs. Monitor macOS betas.

### Risk: External display has no UI
- **Mitigation**: This is intentional behavior, consistent with other notch overlay apps (NotchDrop, Boring Notch). Document this limitation. Fallback could be added later if requested via GitHub issues.

### Risk: Menu bar apps conflict with window level
- **Mitigation**: `.statusBar + 8` is intentionally high. Same level used by NotchDrop without reported issues.

## Migration Plan

1. Create new notch panel implementation alongside existing floating panel
2. Add feature flag or notch detection to route to appropriate panel
3. Remove floating panel code once notch implementation is stable
4. Document non-notch limitation in README/release notes

## Open Questions

- None currently - all clarifications received.
