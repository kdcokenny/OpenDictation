# Design: Migrate to Native Xcode Project

## Context
OpenDictation currently uses Swift Package Manager (SPM) with XcodeGen to generate Xcode projects when needed. This approach:
- Requires developers to run `xcodegen generate` before using Xcode
- Creates friction between SPM and Xcode workflows
- Deviates from patterns used by popular macOS apps

Research of successful macOS apps shows consistent patterns:
- **Gifski** (Sindre Sorhus): Native xcodeproj, Config.xcconfig for versioning, macOS 15.3
- **Loop** (MrKai77): Native xcodeproj, Config.xcconfig, domain-based folders, macOS 13
- **BoringNotch**: Native xcodeproj, components/managers/models structure, macOS 14
- **Stats** (exelban): Native xcodeproj, Kit/Modules separation, macOS 14

## Goals
- Native Xcode project as single source of truth
- Follow best practices from popular macOS apps
- Clean folder structure for maintainability
- Simplified build workflow

## Non-Goals
- App Store distribution (no developer account)
- Code signing with certificates (ad-hoc signing only)
- Changing core app functionality

## Decisions

### 1. Folder Structure
**Decision**: Use domain-based organization following BoringNotch/Loop patterns.

```
OpenDictation/
├── App/                    # App lifecycle
│   ├── OpenDictationApp.swift
│   ├── AppDelegate.swift
│   └── Info.plist
├── Core/                   # Business logic
│   ├── Services/           # All service classes
│   └── Whisper/            # Whisper-specific code
├── Views/                  # All SwiftUI views
├── Models/                 # Data models
├── Extensions/             # Swift extensions
├── Utilities/              # Helper functions
└── Resources/              # Assets, sounds, models
```

**Rationale**: This structure is used by BoringNotch, Loop, and aligns with SwiftUI best practices.

### 2. Version Management
**Decision**: Use `Config.xcconfig` for version numbers.

```
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
```

**Rationale**: Pattern used by Sindre Sorhus (Gifski) and MrKai77 (Loop). Keeps version info in one place, easy to update in CI.

### 3. Dependency Management
**Decision**: Use Xcode's built-in SPM integration.

Dependencies:
- `KeyboardShortcuts` (existing) - Global hotkeys
- `Sparkle` (existing) - Auto-updates
- `Defaults` (new) - Type-safe UserDefaults
- `LaunchAtLogin-Modern` (new) - Launch at login

**Rationale**: All researched apps use SPM packages within Xcode. These specific packages are used by BoringNotch and other Sindre Sorhus apps.

### 4. XCFramework Handling
**Decision**: Keep whisper.xcframework in `Frameworks/` directory, embed in app bundle.

**Rationale**: Standard pattern for binary frameworks. Makefile continues to handle building from source.

### 5. Minimum Deployment Target
**Decision**: macOS 26.0

**Rationale**: User requirement. Targets current stable macOS release.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Breaking existing workflows | Document new workflow in README |
| Loss of SPM simplicity | Makefile provides equivalent commands |
| Xcode project merge conflicts | Use `.xcconfig` for settings, minimize pbxproj changes |

## Migration Plan

1. Create native Xcode project
2. Restructure source files
3. Configure dependencies
4. Update Makefile
5. Test build and run
6. Remove obsolete files (Package.swift, project.yml)
7. Update documentation

## Open Questions
None - all decisions made based on user requirements and research.
