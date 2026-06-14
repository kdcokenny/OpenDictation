# AGENTS.md

## Code Philosophy
- **Elegant Simplicity**: Write the simplest code that solves the problem. Avoid premature abstraction, unnecessary indirection, and over-engineering. If a solution feels complex, step back and find a simpler approach.
- **Fail Fast**: Validate inputs early and throw explicit errors immediately when something is wrong. Never silently swallow errors or continue with invalid state. Use guard clauses at function entry points.
- **Explicit over Implicit**: Prefer clear, obvious code over clever code. Future readers (including AI) should understand intent without mental gymnastics.
