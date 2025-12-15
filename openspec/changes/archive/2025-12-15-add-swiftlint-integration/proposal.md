# Change: Add SwiftLint Integration

## Why
The project currently has no automated code linting or static analysis. Adding SwiftLint will catch common bugs, enforce consistency, and align with best practices used by popular macOS apps like Stats (35k stars), Ice (25k stars), and MonitorControl (32k stars).

## What Changes
- Add `.swiftlint.yml` configuration file (relaxed rules focused on bug catching, not strict style)
- Add SwiftLint as an Xcode build phase (runs on every build, warns if not installed)
- Add `lint` and `lint-fix` targets to Makefile
- Add separate GitHub Actions workflow for CI linting
- Update `project.yml` to include the build phase script

## Impact
- Affected specs: `build-system`
- Affected code:
  - `project.yml` - Add preBuildScripts for SwiftLint
  - `Makefile` - Add lint targets
  - `.github/workflows/lint.yml` - New CI workflow
  - `.swiftlint.yml` - New configuration file
