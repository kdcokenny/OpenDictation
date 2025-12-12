# Change: Add Automatic Updates via Sparkle

## Why

Users currently have no way to receive updates without manually downloading new releases from GitHub. This creates friction and leaves users on outdated versions. Native macOS apps provide seamless, silent updates that "just work" in the background—this is the expected UX for a polished Mac app.

## What Changes

- **NEW: Auto-update capability** using the Sparkle framework (industry standard for macOS apps)
- Add "Check for Updates..." menu item to the status bar menu
- Add Updates section in Settings with toggle controls and version info
- Silent automatic updates: app downloads and installs updates in background without user prompts
- EdDSA signature verification for secure updates (no Apple Developer Program required)
- Daily update checks (86400 seconds)
- Alpha versioning scheme (`0.x.0-alpha` with build numbers)
- GitHub Actions workflow for automated release signing and appcast generation

## Impact

- **Affected specs**: 
  - `auto-update` (new capability)
  - `menu-bar` (add menu item)
- **Affected code**:
  - `Package.swift` - add Sparkle dependency
  - `Info.plist` - add Sparkle configuration keys
  - `AppDelegate.swift` - add menu item, initialize updater
  - `SettingsView.swift` - add Updates section
  - New `Services/UpdateService.swift`
- **New files**:
  - `.github/workflows/release.yml` - automated release workflow
  - `appcast.xml` - update feed
- **External dependency**: Sparkle 2.8.1 (MIT license, widely used)
