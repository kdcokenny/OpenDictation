---
description: Commit changes, push to a new branch, and create a PR
---

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Diff summary: !`git diff --stat`
- Recent commits: !`git log --oneline -5`

## Your task

Commit changes, push to a new branch, and open a Pull Request.

**Optional argument**: Branch name hint (e.g., `/commit-pr fix-auth-bug`). If not provided, generate one from the changes.

### Steps

1. **Analyze changes**: Understand the scope and type of modifications.

2. **Create branch** (if on main/master):
   - If `$ARGUMENTS` provided, derive branch name from it
   - Otherwise, generate from the changes (e.g., `feature/add-user-auth` or `fix/null-pointer-error`)
   - Format: `feature/<slug>` or `fix/<slug>`
   - Run: `git checkout -b <branch-name>`

3. **Stage and commit**:
   - Stage relevant files
   - Commit with Conventional Commits format
   - No AI attribution

4. **Push**: `git push -u origin <branch-name>`

5. **Create PR** using `gh pr create`:
   - Title: Clear, concise description of the change
   - Body: Brief summary explaining what changed and why

   ```bash
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   <concise description of what this PR does and why>

   ## Changes
   - <key change 1>
   - <key change 2>
   EOF
   )"
   ```

6. **Report**: Show the PR URL.
