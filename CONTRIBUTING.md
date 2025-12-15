# Contributing to Open Dictation

Thanks for your interest in contributing! This guide covers the development setup and contribution process.

## Build Environment

- **macOS 14** (Sonoma) or later
- **Xcode 15+** (latest stable recommended)
- **Apple Silicon Mac** (M1 or later)

## Getting Started

### 1. Clone and Setup

```bash
git clone https://github.com/kdcokenny/OpenDictation.git
cd OpenDictation
make setup  # Downloads models and builds whisper.cpp
```

### 2. Build and Run

```bash
make build  # Build debug version
make run    # Run the app
```

See `make help` for all available targets.

## Development with Non-Xcode Editors

If you use VSCode, Cursor, Zed, Neovim, or other editors with sourcekit-lsp, you'll need additional setup for code completion and navigation to work.

### Setup

```bash
brew install xcode-build-server
make lsp  # Generate buildServer.json
```

Then **build once in Xcode GUI** (required for sourcekit-lsp to resolve symbols):

1. Open `OpenDictation.xcodeproj` in Xcode
2. Press **Cmd+B** to build
3. Close Xcode
4. Restart your editor

### Troubleshooting

If symbols stop resolving after significant code changes, rebuild in Xcode GUI (Cmd+B).

## Code Style

We use [SwiftLint](https://github.com/realm/SwiftLint) for code style enforcement.

```bash
brew install swiftlint
make lint      # Check for violations
make lint-fix  # Auto-fix where possible
```

SwiftLint runs automatically during Xcode builds. All violations must be resolved before merging.

### Style Guidelines

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- 2-space indentation, 100 character line width
- Use `///` doc comments
- Name booleans with `is`/`has` prefix (e.g., `isRecording`)
- Prefer guard clauses for early returns

## Pull Requests

1. Fork the repository
2. Create a feature branch (`feat/my-feature` or `fix/my-bug`)
3. Make your changes
4. Ensure `make lint` passes
5. Ensure `make build` succeeds
6. Submit a pull request against `main`

### Commit Messages

Use [conventional commits](https://www.conventionalcommits.org/):

- `feat:` new features
- `fix:` bug fixes
- `refactor:` code changes that neither fix bugs nor add features
- `docs:` documentation only
- `test:` adding/updating tests

## Project Structure

```
OpenDictation/
├── App/              # App lifecycle (AppDelegate, main entry)
├── Core/
│   ├── Services/     # Business logic services
│   ├── Utilities/    # Helpers and extensions
│   └── Whisper/      # Whisper.cpp integration
├── Models/           # Data models
├── Resources/        # Assets, sounds, bundled models
└── Views/            # SwiftUI views
```

## Need Help?

- Check existing [issues](https://github.com/kdcokenny/OpenDictation/issues)
- Open a new issue for bugs or feature requests
