---
description: Create a new git worktree for the given topic
---

## Context

- Repo name: !`basename $(git rev-parse --show-toplevel)`
- Current branch: !`git branch --show-current`
- Existing worktrees: !`git worktree list`

## Your task

Create a new git worktree for working on: **$ARGUMENTS**

Follow these steps:

1. **Generate a branch name** from the topic "$ARGUMENTS":
   - Convert to lowercase, replace spaces with hyphens
   - Format: `feature/<topic-slug>` or `fix/<topic-slug>` based on context
   - Keep it concise (max 50 chars for the slug)

2. **Create the worktree** in `~/workspace/.worktrees/`:
   - Directory: `<repo-name>-<topic-slug>`
   - Command: `git worktree add -b <branch-name> ~/workspace/.worktrees/<directory-name>`

3. **Report**: Show worktree path, branch name, and `cd` command.
