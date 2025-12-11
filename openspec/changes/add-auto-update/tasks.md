# Tasks: Add Automatic Updates

## 1. Setup

- [x] 1.1 Add Sparkle dependency to Package.swift (sparkle-project/Sparkle 2.8.1)
- [x] 1.2 Verify build succeeds with new dependency

## 2. Configuration

- [x] 2.1 Update Info.plist with Sparkle configuration keys:
  - SUFeedURL (appcast URL)
  - SUPublicEDKey (placeholder, user fills in)
  - SUEnableAutomaticChecks (true)
  - SUAllowsAutomaticUpdates (true)
  - SUAutomaticallyUpdate (true)
  - SUScheduledCheckInterval (86400)
- [x] 2.2 Update version scheme to alpha format:
  - CFBundleShortVersionString: 0.1.0-alpha
  - CFBundleVersion: 1

## 3. UpdateService Implementation

- [x] 3.1 Create Services/UpdateService.swift:
  - SPUStandardUpdaterController initialization
  - Published canCheckForUpdates property
  - checkForUpdates() method
  - Singleton pattern (UpdateService.shared)

## 4. Menu Bar Integration

- [x] 4.1 Add "Check for Updates..." menu item to AppDelegate.swift
  - Position before "Settings..." with separator
  - Wire to UpdateService.shared.checkForUpdates()

## 5. Settings UI

- [x] 5.1 Add Updates section to SettingsView.swift:
  - Toggle: "Automatically check for updates"
  - Toggle: "Automatically download and install updates"
  - Button: "Check Now"
  - Version display: "Version 0.1.0-alpha (build 1)"

## 6. Release Infrastructure

- [x] 6.1 Create initial appcast.xml (empty feed structure)
- [x] 6.2 Create .github/workflows/release.yml:
  - Trigger on v* tags
  - Build app
  - Create DMG
  - Sign with Sparkle EdDSA key
  - Generate appcast entry
  - Create GitHub Release with DMG
  - Commit updated appcast.xml

## 7. Documentation

- [x] 7.1 Add setup instructions to README:
  - Key generation steps
  - GitHub secret configuration
  - Release process

## 8. Validation

- [ ] 8.1 Test manual "Check for Updates" works
- [ ] 8.2 Test Settings toggles persist correctly
- [x] 8.3 Verify appcast.xml is valid XML
- [ ] 8.4 Test release workflow (dry run or actual release)
