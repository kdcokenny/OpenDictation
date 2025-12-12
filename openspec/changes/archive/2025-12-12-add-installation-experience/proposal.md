# Change: Add polished installation experience

## Why

The current installation experience lacks polish compared to beloved macOS apps. Users download a basic DMG without visual guidance, and if they run the app from the DMG or Downloads folder, it doesn't prompt them to move to Applications. A native-feeling macOS app should have a beautiful drag-to-install DMG and gracefully handle improper installation locations.

## What Changes

- Add styled DMG with custom background showing app icon, arrow, and Applications folder drop target
- Add ApplicationMover service that detects when running from DMG or temporary locations (Downloads, Desktop, Documents) and offers to move to Applications
- Add custom app icon (mic + cursor design with teal-purple gradient)
- Add custom menu bar icon (monochrome template image) to differentiate from system mic icon
- Add volume icon (.icns) for DMG appearance in Finder sidebar
- Update build process to use `create-dmg` for styled DMG generation

## Impact

- **Affected specs**: `menu-bar` (custom icon), new `installation` capability
- **Affected code**:
  - `Sources/OpenDictation/Resources/Assets.xcassets/` (new asset catalog)
  - `Sources/OpenDictation/Services/ApplicationMover.swift` (new)
  - `Sources/OpenDictation/AppDelegate.swift` (call ApplicationMover, use custom menu icon)
  - `Makefile` (update `dmg` target with `create-dmg`)
  - `.github/workflows/release.yml` (add `create-dmg` dependency)
  - `project.yml` (reference asset catalog)
