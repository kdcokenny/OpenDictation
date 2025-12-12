# Tasks: Migrate to Native Xcode Project

## 1. Project Setup
- [x] 1.1 Create `Config.xcconfig` with version settings
- [x] 1.2 Create native `OpenDictation.xcodeproj` in Xcode
- [x] 1.3 Configure build settings (macOS 26.0, Swift 6, ad-hoc signing)

## 2. Folder Restructure
- [x] 2.1 Create new folder structure (App/, Core/, Views/, Models/, Extensions/, Utilities/)
- [x] 2.2 Move app lifecycle files to App/ (OpenDictationApp.swift, AppDelegate.swift, Info.plist)
- [x] 2.3 Move services to Core/Services/
- [x] 2.4 Move Whisper-related files to Core/Whisper/
- [x] 2.5 Move views to Views/
- [x] 2.6 Move models to Models/
- [x] 2.7 Update any import paths if needed

## 3. Dependencies
- [x] 3.1 Add KeyboardShortcuts package via Xcode SPM
- [x] 3.2 Add Sparkle package via Xcode SPM
- [x] 3.3 Add Defaults package via Xcode SPM
- [x] 3.4 Add LaunchAtLogin-Modern package via Xcode SPM
- [x] 3.5 Move whisper.xcframework to Frameworks/ directory (symlink)
- [x] 3.6 Configure whisper.xcframework as embedded framework

## 4. Swift 6 Concurrency Fixes
- [x] 4.1 Convert CloudTranscriptionProvider to actor
- [x] 4.2 Convert TranscriptionCoordinator to actor
- [x] 4.3 Convert VADModelManager to actor
- [x] 4.4 Add @MainActor to UpdateService
- [x] 4.5 Add @MainActor to RecordingService
- [x] 4.6 Add @MainActor to ModelDownloader
- [x] 4.7 Add @unchecked Sendable to KeychainService
- [x] 4.8 Fix DictationOverlayPanel deinit issue
- [x] 4.9 Fix delegate protocol conformance (nonisolated methods)
- [x] 4.10 Fix PermissionsManager accessibility constant access
- [x] 4.11 Update callers for actor changes (AppDelegate)

## 5. Build Configuration
- [x] 5.1 Update Makefile to use xcodebuild commands
- [x] 5.2 Remove swift build/run commands from Makefile
- [x] 5.3 Update CI workflow (.github/workflows/release.yml) for native Xcode (existing workflow already uses xcodebuild)

## 6. Cleanup
- [x] 6.1 Remove Package.swift
- [x] 6.2 Remove Package.resolved
- [x] 6.3 Remove Sources/ directory (replaced by OpenDictation/)
- [x] 6.4 Remove .build/ directory (SPM cache)
- [x] 6.5 Update README.md with new build instructions
- [x] 6.6 Update RELEASING.md if needed

## 7. Validation
- [x] 7.1 Verify `make setup` works (framework + models)
- [x] 7.2 Verify `make build` works (xcodebuild debug)
- [x] 7.3 Verify `make release` works
- [x] 7.4 Verify `make dmg` works
- [x] 7.5 Test app launches and functions correctly
