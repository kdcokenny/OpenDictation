# Contributing to Open Dictation

Open Dictation requires macOS 14 or later, Xcode 26 or later, and an Apple Silicon Mac. Install the development tools with Homebrew:

```bash
brew install xcodegen swiftlint
```

## Set up a checkout

```bash
git clone https://github.com/kdcokenny/OpenDictation.git
cd OpenDictation
make setup
```

`make setup` downloads the pinned whisper.cpp XCFramework, verifies every downloaded binary, downloads the bundled Whisper models when needed, and regenerates `OpenDictation.xcodeproj` from `project.yml`. The generated project is intentionally ignored by Git. Run `make setup` again after changing `project.yml`.

The pinned binary versions, immutable model revisions, and SHA-256 hashes live in `scripts/dependencies.env`.

## Build and test

```bash
make build
make test
make lint
```

`make ci` runs SwiftLint, the macOS unit tests, and a clean Release build. It also checks that the built app contains the whisper.cpp framework and the two bundled models. Run it before opening a pull request.

Use `make run` to open the development app. `make help` lists the other targets.

## SourceKit-LSP editors

For VS Code, Cursor, Zed, Neovim, or another SourceKit-LSP editor, install `xcode-build-server` and generate its project configuration:

```bash
brew install xcode-build-server
make lsp
```

Run `make build` once to populate the index, then restart the editor. Repeat those steps if project generation or a large source change leaves stale symbols.

## Code style

Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/). This project uses two-space indentation and a 100-character line width. Prefer guard clauses for invalid input and use `is` or `has` prefixes for Boolean properties.

SwiftLint runs during Xcode builds when it is installed. CI also runs `swiftlint --strict` directly. `make lint-fix` applies SwiftLint's safe automatic corrections, then runs the strict check again.

## Pull requests

Create a focused feature or fix branch, include tests for changed behavior, and run `make ci`. Use conventional commit prefixes such as `feat:`, `fix:`, `refactor:`, `docs:`, and `test:`.

Open pull requests against `main`. Describe the user-visible behavior and list the checks you ran.

## Project layout

```text
OpenDictation/
├── App/              App lifecycle and configuration
├── Core/             Services, context, utilities, and speech engines
├── Models/           App data models
├── Resources/        Assets, sounds, DMG artwork, and bundled models
└── Views/            SwiftUI and AppKit views
```
