# Tasks: Add Installation Experience

## 1. Asset Preparation

Source assets located at: `/Users/kenny/Documents/OpenDictation-Assets/`
- `OpenDictationAppIcon.png` (1024x1024) - App icon
- `OpenDictationIcon.svg` - Menu bar icon (mic + cursor silhouette)
- `OpenDictationDMGInstaller.jpeg` (2528x1696) - DMG background

- [x] 1.1 Create `Assets.xcassets` directory structure
- [x] 1.2 Generate app icon sizes from 1024x1024 source (16, 32, 128, 256, 512 at 1x and 2x)
- [x] 1.3 Create `AppIcon.appiconset/Contents.json` manifest
- [x] 1.4 Convert SVG menu bar icon to PNG (18x18 @1x, 36x36 @2x)
- [x] 1.5 Create `MenuBarIcon.imageset/Contents.json` as template image
- [x] 1.6 Generate `.icns` volume icon from app icon source
- [x] 1.7 Copy DMG background image to resources

## 2. ApplicationMover Service

- [x] 2.1 Create `ApplicationMover.swift` with DMG detection logic (`statfs`, `hdiutil info`)
- [x] 2.2 Implement temporary location detection (Downloads, Desktop, Documents)
- [x] 2.3 Implement "Move to Applications?" alert dialog
- [x] 2.4 Implement file copy and existing app replacement logic (including detection of running app at destination)
- [x] 2.5 Implement relaunch from new location

## 3. App Integration

- [x] 3.1 Update `AppDelegate.swift` to call `ApplicationMover.checkAndOfferToMoveToApplications()` on launch
- [x] 3.2 Update `AppDelegate.swift` to use custom menu bar icon from asset catalog
- [x] 3.3 Update `project.yml` to reference asset catalog

## 4. Build System Updates

- [x] 4.1 Update `Makefile` `dmg` target to use `create-dmg` (Homebrew: `brew install create-dmg`) with background, icon positions, and volume icon
- [x] 4.2 Update `.github/workflows/release.yml` to install `create-dmg` via Homebrew and use new DMG generation
- [x] 4.3 Test DMG generation locally with `make dmg`

## 5. Validation

- [x] 5.1 Verify app icon appears correctly in Dock and Finder
- [x] 5.2 Verify menu bar icon renders correctly in light and dark mode
- [x] 5.3 Verify DMG opens with styled background and correct icon positions
- [x] 5.4 Verify ApplicationMover detects DMG launch and offers to move
- [x] 5.5 Verify move to Applications and relaunch works correctly
