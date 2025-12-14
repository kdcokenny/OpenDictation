# Tasks: Automated Version Management

## 1. Update Config.xcconfig to Placeholder Values
- [x] 1.1 Set MARKETING_VERSION to 0.0.0-dev
- [x] 1.2 Set CURRENT_PROJECT_VERSION to 0
- [x] 1.3 Add comment explaining these are placeholders

## 2. Update Release Workflow
- [x] 2.1 Add "Inject version into built app" step after build, before signing
  - Extract marketing version from tag (e.g., `v0.1.10-alpha` -> `0.1.10-alpha`)
  - Use PlistBuddy to set CFBundleShortVersionString to $VERSION
  - Use PlistBuddy to set CFBundleVersion to $GITHUB_RUN_NUMBER
  - Add verification step to confirm version was set
- [x] 2.2 Remove circular commit logic
  - Remove Config.xcconfig from git staging
  - Keep only appcast.xml commit (still needed for Sparkle)

## 3. Clean Up Unnecessary Changes
- [x] 3.1 Revert project.yml changes
  - Remove VERSIONING_SYSTEM setting (not needed with PlistBuddy)
  - Remove CURRENT_PROJECT_VERSION reference
  - Remove MARKETING_VERSION reference

## 4. Update Spec Documentation
- [x] 4.1 Update build-system spec to reflect new approach
  - Modify "Version Configuration" requirement
  - Document PlistBuddy injection as the version mechanism
  - Clarify git tag as single source of truth

## 5. Validation
- [x] 5.1 Test release workflow with a new alpha tag
  - Create test tag (e.g., v0.1.11-alpha)
  - Verify Config.xcconfig remains unchanged (still 0.0.0-dev)
  - Verify built app has correct version in Info.plist
  - Verify appcast.xml has matching version
  - Verify DMG installs and shows correct version
  - Verify DMG installs and shows correct version
