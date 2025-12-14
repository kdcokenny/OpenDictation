## MODIFIED Requirements

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
