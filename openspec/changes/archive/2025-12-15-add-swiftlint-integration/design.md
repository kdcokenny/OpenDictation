# Design: SwiftLint Integration

## Context
This change adds automated Swift linting to the project. The design is based on research into how the most popular open-source macOS apps implement linting:

| App | Stars | SwiftLint | Xcode Build Phase | CI Workflow |
|-----|-------|-----------|-------------------|-------------|
| Stats | 35k | Yes | Yes | Yes (lenient) |
| Ice | 25k | Yes | Yes | Yes (strict) |
| MonitorControl | 32k | Yes | N/A | N/A |
| Maccy | 18k | Yes | No | No |

## Goals
- Catch bugs and common mistakes early
- Maintain code consistency without being overly strict
- Integrate seamlessly into developer workflow (Xcode + CLI)
- Non-blocking CI (warnings don't fail builds)

## Non-Goals
- Strict style enforcement (line length limits, etc.)
- SwiftFormat integration (code formatting)
- Periphery integration (dead code detection)
- Breaking CI on lint warnings

## Decisions

### Decision: Relaxed Configuration (Stats/Ice Pattern)
**What:** Disable strict style rules, focus on bug-catching rules only.

**Why:** Both Stats and Ice disable rules like `line_length`, `function_body_length`, `identifier_name`. This prevents lint noise while catching actual issues.

**Alternatives considered:**
- Strict configuration: Rejected - creates friction without catching more bugs
- No configuration (defaults): Rejected - too noisy for real-world code

### Decision: Xcode Build Phase with Graceful Fallback
**What:** Add SwiftLint as a build phase that shows a warning (not error) if SwiftLint isn't installed.

**Why:** Both Stats and Ice use this pattern. It encourages linting without forcing every developer to install SwiftLint.

**Script pattern (from Ice):**
```bash
if [[ "$(uname -m)" == arm64 ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

if which swiftlint > /dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

### Decision: Separate CI Workflow (Non-Blocking)
**What:** Create a dedicated `lint.yml` workflow that runs SwiftLint in CI without the `--strict` flag.

**Why:** Stats uses this approach - linting runs but doesn't block PRs. Ice uses `--strict` which fails on warnings, but for a project just starting with linting, the lenient approach is better.

**Alternatives considered:**
- Integrate into existing release workflow: Rejected - linting should run on all PRs, not just releases
- Use `--strict` flag: Rejected - too aggressive for initial adoption

### Decision: Use norio-nomura/action-swiftlint GitHub Action
**What:** Use the `norio-nomura/action-swiftlint@3.2.1` action for CI.

**Why:** Both Stats and Ice use this exact action. It runs on `ubuntu-latest` (fast, free) and produces nice inline annotations.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Existing code may have lint violations | Use relaxed config to minimize initial violations; fix issues incrementally |
| Developers without SwiftLint see warnings | Warning is informational only, doesn't break build |
| CI runs on every Swift file change | Efficient - runs on ubuntu-latest, takes ~30 seconds |

## Open Questions
None - design is straightforward based on established patterns from popular apps.
