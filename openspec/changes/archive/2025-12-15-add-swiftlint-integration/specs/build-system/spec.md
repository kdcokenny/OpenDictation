## ADDED Requirements

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
