---
description: Bump version, create a git tag, and push release
---

## Context

- Current branch: !`git branch --show-current`
- Latest tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "No tags found"`
- Recent commits: !`git log --oneline -5`

## Your task

Create a new version, tag it, and push to trigger the release workflow.

**Required argument**: Version bump type (`patch`, `minor`, or `major`)

Example: `/push-release patch`

### Steps

1. **Parse the argument**: Extract the bump type from `$ARGUMENTS` (e.g., `patch`, `minor`, `major`)

2. **Get current version**:
   - Run `git describe --tags --abbrev=0` to get the latest tag (e.g., `v0.1.8-alpha`)
   - Extract the semantic version and suffix (e.g., `0.1.8` and `-alpha`)

3. **Bump the version**:
   - Parse the current version (e.g., `0.1.8`)
   - Apply the bump type:
     - `patch`: increment patch (0.1.8 → 0.1.9)
     - `minor`: increment minor, reset patch (0.1.8 → 0.2.0)
     - `major`: increment major, reset minor and patch (0.1.8 → 1.0.0)
   - Preserve the `-alpha` suffix (e.g., 0.1.9-alpha)

4. **Create and push tag**:
   - Run `git tag v<new-version>` (e.g., `git tag v0.1.9-alpha`)
   - Run `git push origin v<new-version>` to trigger the release workflow

5. **Report**: Show the new version tag and confirm the release has been initiated.
