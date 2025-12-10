<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# AGENTS.md

## Code Philosophy
- **Elegant Simplicity**: Write the simplest code that solves the problem. Avoid premature abstraction, unnecessary indirection, and over-engineering. If a solution feels complex, step back and find a simpler approach.
- **Fail Fast**: Validate inputs early and throw explicit errors immediately when something is wrong. Never silently swallow errors or continue with invalid state. Use guard clauses at function entry points.
- **Explicit over Implicit**: Prefer clear, obvious code over clever code. Future readers (including AI) should understand intent without mental gymnastics.
