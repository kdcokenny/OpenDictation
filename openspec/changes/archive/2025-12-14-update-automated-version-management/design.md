# Design: Automated Version Management

## Context

The release workflow extracts version from git tags (e.g., `v0.1.10-alpha`) but the build uses versions from `Config.xcconfig`. When a release is created, the appcast is updated automatically but Config.xcconfig remains stale. This disconnect caused users to be stuck on old versions.

**Research of popular macOS apps** (Ghostty 28k⭐, CodeEdit 22k⭐, Loop 5k⭐) shows three approaches:
1. **Ghostty**: Inject version into built app with PlistBuddy - no version in source
2. **CodeEdit**: Use agvtool with native Xcode project (no xcodegen)
3. **Loop**: Use sed to update xcconfig (like us, uses xcodegen)

**Key finding**: agvtool doesn't work with xcconfig-based versioning - it modifies Info.plist directly, breaking variable references like `$(MARKETING_VERSION)`.

## Goals / Non-Goals

**Goals:**
- Single source of truth: Git tag is the version
- Zero synchronization: Eliminate version drift between files
- Fewer failure points: Simpler = more reliable
- Clean git history: No circular commits

**Non-Goals:**
- Showing real version in source files (placeholder values acceptable)
- Committing version changes back to repository
- Multi-configuration version management

## Decisions

### Decision 1: Use PlistBuddy to inject version into built app (Ghostty's approach)
**What:** After building the app, use `/usr/libexec/PlistBuddy` to inject version into the built `.app/Contents/Info.plist`.

**Why:** 
- **Single source of truth**: Git tag is the only place version is defined
- **No sync issues**: Can't have version drift if version only exists in one place
- **Simpler workflow**: One command vs. sed + git add + git commit + git push
- **Proven at scale**: Ghostty (28k stars) uses this successfully
- **Works with xcodegen**: Doesn't conflict with generated project files
- **Clean git history**: No circular commits cluttering history

**Alternatives considered:**
1. **agvtool** - Doesn't work with xcconfig variables, breaks `$(MARKETING_VERSION)` references
2. **sed on xcconfig** - Works but requires committing back, creates sync complexity
3. **Current approach** - Manual updates proven to fail

### Decision 2: Inject version after build, before signing
**What:** Add PlistBuddy step after xcodebuild, before codesigning.

**Why:**
- App bundle must exist before we can modify Info.plist
- Version must be set before signing (signature includes plist)
- Version must be set before creating DMG

### Decision 3: Keep placeholder values in Config.xcconfig
**What:** Set `MARKETING_VERSION = 0.0.0-dev` and `CURRENT_PROJECT_VERSION = 0` in source.

**Why:**
- Local/dev builds show "0.0.0-dev" which accurately reflects they're not releases
- Source files never change per-release
- No merge conflicts on version numbers
- Easier to understand: if it's not from a tagged release, it shows dev version

### Decision 4: Use GITHUB_RUN_NUMBER for build number
**What:** Continue using `GITHUB_RUN_NUMBER` as the incrementing build number.

**Why:**
- Already in use, works well
- Monotonically increasing
- No additional state to manage
- Sparkle uses this to determine update ordering

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Local builds show "0.0.0-dev" | Acceptable - dev builds aren't releases |
| Version not visible in source | Git tag is the version, more correct conceptually |
| PlistBuddy could fail | Simple tool, unlikely; workflow will fail fast if it does |

**Trade-off Analysis:**
- **Give up**: Version visibility in source files
- **Gain**: Reliability, simplicity, zero sync issues, clean git history

## Migration Plan

1. Update Config.xcconfig to placeholder values
2. Update release.yml with PlistBuddy injection
3. Remove circular commit logic
4. Test with a new alpha release
5. Verify built app has correct version

## Open Questions

None - approach is validated by Ghostty, a highly-respected macOS project.
