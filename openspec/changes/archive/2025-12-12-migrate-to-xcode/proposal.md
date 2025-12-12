# Change: Migrate from Swift Package Manager to Native Xcode Project

## Why
The current build system uses Swift Package Manager with XcodeGen as a bridge, which adds complexity and deviates from industry best practices. Native Xcode projects are the standard for macOS app development, used by well-designed apps like Gifski (Sindre Sorhus), Loop (MrKai77), BoringNotch, and Stats.

## What Changes
- Replace `Package.swift` and `project.yml` with native `.xcodeproj`
- Restructure source folders to follow best practices (App/Core/Views/Models pattern)
- Add `Config.xcconfig` for version management (following Sindre Sorhus pattern)
- Add `Defaults` package for type-safe UserDefaults
- Add `LaunchAtLogin-Modern` package for launch-at-login functionality
- Update Makefile to use xcodebuild directly
- Target macOS 26.0 minimum deployment
- Update CI workflow for native Xcode builds

## Impact
- Affected specs: build-system (new capability)
- Affected code: All source files (folder restructure), Makefile, CI workflow
- **BREAKING**: Removes `swift build` and `swift run` commands - use Xcode or `make build` instead
