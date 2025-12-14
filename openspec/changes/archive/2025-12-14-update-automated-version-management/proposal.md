# Change: Automate Version Management with PlistBuddy

## Why
The current release workflow updates `appcast.xml` automatically but leaves `Config.xcconfig` out of sync. This caused production users to be stuck at version 0.1.8-alpha while 0.1.10-alpha was released. The root cause is maintaining version in multiple places (git tag, Config.xcconfig, appcast.xml), requiring error-prone synchronization.

## What Changes
- Inject version directly into built app bundle using `PlistBuddy` (like Ghostty)
- Git tag becomes the single source of truth for version
- Remove need to commit version changes back to repository
- Eliminate sync issues between Config.xcconfig and releases

## Impact
- Affected specs: `build-system`
- Affected code:
  - `.github/workflows/release.yml` - Add PlistBuddy version injection after build
  - `Config.xcconfig` - Set to placeholder values (0.0.0-dev)
  - Remove circular commits for version updates
- **BREAKING**: None - this is a CI/CD improvement, not a user-facing change
