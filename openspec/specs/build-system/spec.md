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

### Requirement: LSP Support for Non-Xcode Editors
The project SHALL support SourceKit LSP integration for developers using non-Xcode editors (VSCode, Cursor, Neovim, etc.) via xcode-build-server.

#### Scenario: Generate LSP configuration
- **WHEN** developer runs `make lsp`
- **THEN** xcode-build-server generates a `buildServer.json` file in the project root
- **AND** the configuration points to the correct Xcode project and scheme
- **AND** if xcode-build-server is not installed, a helpful error message is displayed

#### Scenario: Auto-generate LSP config during build
- **WHEN** developer runs `make build` without a `buildServer.json` file
- **THEN** the build process automatically runs `make lsp` first
- **AND** then proceeds with the normal build

#### Scenario: LSP configuration not committed
- **WHEN** developer generates `buildServer.json`
- **THEN** the file is ignored by git (listed in `.gitignore`)
- **AND** each developer generates their own local configuration

#### Scenario: SourceKit LSP resolves project types
- **WHEN** developer opens a Swift file in a non-Xcode editor with sourcekit-lsp
- **AND** `buildServer.json` exists
- **AND** the project has been built at least once
- **THEN** the editor correctly resolves types from other project files
- **AND** the editor correctly resolves types from Swift Package dependencies

### Requirement: SwiftLint Integration
The build system SHALL integrate SwiftLint for automated code linting to catch bugs and enforce consistency.

#### Scenario: Xcode build with SwiftLint installed
- **WHEN** developer builds the project in Xcode
- **AND** SwiftLint is installed via Homebrew
- **THEN** SwiftLint runs as a build phase
- **AND** any violations appear as Xcode warnings or errors

#### Scenario: Xcode build without SwiftLint installed
- **WHEN** developer builds the project in Xcode
- **AND** SwiftLint is NOT installed
- **THEN** the build succeeds
- **AND** Xcode displays a warning: "SwiftLint not installed"

#### Scenario: Run lint from command line
- **WHEN** developer runs `make lint`
- **THEN** SwiftLint analyzes all Swift files in `OpenDictation/`
- **AND** violations are printed to stdout

#### Scenario: Auto-fix lint violations
- **WHEN** developer runs `make lint-fix`
- **THEN** SwiftLint runs with `--fix` flag
- **AND** auto-correctable violations are fixed in place

### Requirement: CI Linting Workflow
The project SHALL have a dedicated GitHub Actions workflow for linting that runs on Swift file changes.

#### Scenario: PR with Swift changes triggers lint
- **WHEN** a pull request is opened or updated
- **AND** the PR includes changes to `.swift` files or `.swiftlint.yml`
- **THEN** the lint workflow runs automatically

#### Scenario: Push with Swift changes triggers lint
- **WHEN** code is pushed to any branch
- **AND** the push includes changes to `.swift` files or `.swiftlint.yml`
- **THEN** the lint workflow runs automatically

#### Scenario: Lint violations reported in PR
- **WHEN** the lint workflow finds violations
- **THEN** violations appear as annotations on the PR
- **AND** the workflow completes (does not fail the PR)

