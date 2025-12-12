# Design: Installation Experience

## Context

Users expect a polished installation experience from macOS apps. Research of beloved apps (Boring Notch, VibeMeter, Sindre Sorhus apps, MonitorControl) revealed common patterns:

1. **DMG Styling**: Custom background with app icon, arrow, and Applications folder symlink
2. **ApplicationMover**: Detection of improper installation locations with offer to move
3. **Custom Icons**: Distinctive app and menu bar icons that match the app's identity

## Goals / Non-Goals

**Goals:**
- Create a professional, Apple-like installation experience
- Guide users to install in Applications folder
- Differentiate from system icons with custom app identity

**Non-Goals:**
- Complex onboarding wizard (permissions are requested contextually when needed)
- Welcome sounds or animations
- Keyboard shortcut customization during installation

## Decisions

### Decision: Use `create-dmg` for DMG styling

**What:** Use the `create-dmg` tool (Homebrew version) for generating styled DMGs.

**Installation:** `brew install create-dmg`

**Why:** 
- Industry standard tool used by many macOS apps
- Handles background images, icon positioning, and Applications symlink
- Simple command-line interface integrates well with Makefile
- Supports codesigning and notarization
- Homebrew version is a shell script with no additional runtime dependencies

**Alternatives considered:**
- Manual hdiutil + AppleScript: More complex, error-prone
- dmgbuild (Python): Additional dependency, less widely used
- create-dmg (npm): Requires Node.js runtime

### Decision: ApplicationMover based on VibeMeter pattern

**What:** Implement ApplicationMover service using `statfs()` for mount detection and `hdiutil info` for DMG verification.

**Why:**
- Proven implementation from VibeMeter (MIT licensed)
- Handles edge cases: DMG detection, temporary folder detection, existing app replacement
- Single dialog UX - minimal friction

**Implementation approach:**
1. Check if already in `/Applications/` or `~/Applications/`
2. Check if running from DMG using `statfs()` + `hdiutil info -plist`
3. Check if running from Downloads/Desktop/Documents
4. If any temporary location detected, show move dialog
5. Copy to Applications, offer to relaunch

### Decision: Menu bar icon as template image

**What:** Use a monochrome PNG marked as template image, not an SF Symbol.

**Why:**
- Differentiates from system `mic.fill` icon
- macOS automatically handles light/dark mode adaptation
- Matches the app icon design (mic + cursor motif)

### Decision: Include volume icon (.icns)

**What:** Generate `.icns` file for DMG volume icon.

**Why:**
- Shows in Finder sidebar when DMG is mounted
- Professional touch that top apps include
- Generated from same source as app icon

## Risks / Trade-offs

### Risk: `hdiutil info` may fail in sandboxed environment
**Mitigation:** Fall back to path-based detection if hdiutil fails. The path check for `/Volumes/` prefix is a reliable secondary indicator.

### Risk: File copy may fail due to permissions
**Mitigation:** Use standard FileManager copy with user-visible error messages. User can always manually drag to Applications.

## Asset Pipeline

```
Source files (located at /Users/kenny/Documents/OpenDictation-Assets/):
- OpenDictationAppIcon.png (1024x1024) → AppIcon.appiconset (all sizes)
- OpenDictationIcon.svg → MenuBarIcon.imageset (22x22, 44x44 PNG)
- OpenDictationAppIcon.png → VolumeIcon.icns (for DMG)
- OpenDictationDMGInstaller.jpeg (2528x1696) → DMG background

Generated artifacts:
- Assets.xcassets/AppIcon.appiconset/ (16, 32, 128, 256, 512 at 1x+2x)
- Assets.xcassets/MenuBarIcon.imageset/ (template image)
- Resources/DMG/background.jpeg
- Resources/DMG/VolumeIcon.icns

Note: DMG background and VolumeIcon.icns are only used during DMG creation,
not bundled in the app. They should be in a build resources location.
```

## Open Questions

None - all design decisions resolved based on research of existing apps.
