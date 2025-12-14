# build-system Specification

## Purpose
TBD - created by archiving change migrate-to-xcode. Update Purpose after archive.
## Requirements
### Requirement: Native Xcode Project
The project SHALL use a native Xcode project (`.xcodeproj`) as the single source of truth for build configuration.

#### Scenario: Developer opens project in Xcode
- **WHEN** developer opens `OpenDictation.xcodeproj` in Xcode
- **THEN** the project loads without requiring any generation steps
- **AND** all source files, resources, and dependencies are properly configured

#### Scenario: Build from command line
- **WHEN** developer runs `make build`
- **THEN** xcodebuild compiles the project successfully
- **AND** the app is placed in the build output directory

### Requirement: Version Configuration
The project SHALL use git tags as the single source of truth for version, with version injected into the built app bundle during the release workflow using `PlistBuddy`.

#### Scenario: Placeholder version in source
- **WHEN** developer checks out the source code
- **THEN** `Config.xcconfig` contains `MARKETING_VERSION = 0.0.0-dev`
- **AND** `Config.xcconfig` contains `CURRENT_PROJECT_VERSION = 0`
- **AND** local builds display "0.0.0-dev" as the version

#### Scenario: Automated version injection during release
- **WHEN** a release is triggered by pushing a version tag (e.g., `v0.1.10-alpha`)
- **THEN** the release workflow extracts the version from the tag
- **AND** builds the app with placeholder values
- **AND** runs `PlistBuddy` to set `CFBundleShortVersionString` in the built app's Info.plist
- **AND** runs `PlistBuddy` to set `CFBundleVersion` in the built app's Info.plist
- **AND** does NOT commit any version changes back to the repository

#### Scenario: Version consistency
- **WHEN** a release build completes
- **THEN** the version in the built app's Info.plist matches the git tag
- **AND** the version in `appcast.xml` matches the git tag
- **BUT** the version in source `Config.xcconfig` remains at placeholder values

#### Scenario: Version inspection
- **WHEN** maintainer needs to check what version was released
- **THEN** they examine the git tag (e.g., `v0.1.10-alpha`)
- **AND** the git tag is the authoritative version identifier

### Requirement: Minimum Deployment Target
The project SHALL target macOS 26.0 as the minimum supported version.

#### Scenario: Build for macOS 26
- **WHEN** the project is built
- **THEN** `MACOSX_DEPLOYMENT_TARGET` is set to 26.0
- **AND** the resulting app runs on macOS 26.0 and later

### Requirement: Source Organization
The project SHALL organize source files into domain-based folders.

#### Scenario: Finding app lifecycle code
- **WHEN** developer looks for app startup code
- **THEN** they find it in the `App/` folder
- **AND** this includes `OpenDictationApp.swift`, `AppDelegate.swift`, and `Info.plist`

#### Scenario: Finding service code
- **WHEN** developer looks for business logic
- **THEN** they find services in `Core/Services/`
- **AND** Whisper-specific code in `Core/Whisper/`

#### Scenario: Finding UI code
- **WHEN** developer looks for SwiftUI views
- **THEN** they find them in the `Views/` folder

### Requirement: Dependency Management
The project SHALL manage Swift package dependencies through Xcode's built-in SPM integration.

#### Scenario: Adding a new dependency
- **WHEN** developer needs to add a Swift package
- **THEN** they use Xcode's File > Add Package Dependencies menu
- **AND** the dependency is tracked in the `.xcodeproj` file

### Requirement: XCFramework Integration
The project SHALL embed `whisper.xcframework` as a framework dependency.

#### Scenario: Building with whisper support
- **WHEN** the project is built
- **THEN** `whisper.xcframework` is embedded in the app bundle
- **AND** the framework is located in `Frameworks/` directory in the repository

