---
description: Stage and commit changes with a conventional commit message
---

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Recent commits: !`git log --oneline -5`

## Your task

Create a git commit for the current changes.

1. **Analyze changes**: Review modified files and determine the type (feat, fix, refactor, docs, etc.)

2. **Stage files**: Stage relevant files using `git add`. Be selective—don't stage unrelated changes.

3. **Craft commit message**:
   - Format: `<type>(<scope>): <subject>`
   - Types: feat, fix, chore, refactor, docs, style, test, perf
   - Focus on WHY, not just WHAT
   - No AI attribution or watermarks

4. **Commit**: Run `git commit -m "<message>"`. If pre-commit hooks modify files, amend to include them.

5. **Report**: Show commit hash, message, and files committed.
