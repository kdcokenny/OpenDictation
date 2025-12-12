## ADDED Requirements

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
The project SHALL use `Config.xcconfig` for version management.

#### Scenario: Version update
- **WHEN** maintainer needs to update the version
- **THEN** they edit only `Config.xcconfig`
- **AND** both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are defined in this file

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
