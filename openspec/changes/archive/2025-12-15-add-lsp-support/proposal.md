# Change: Add LSP Support for Non-Xcode Editors

## Why
Developers using VSCode, Cursor, Neovim, or other editors with sourcekit-lsp currently see false-positive errors (e.g., "Cannot find type 'WhisperModel' in scope") because SourceKit LSP doesn't understand Xcode project structure. This creates a poor developer experience and makes it harder for contributors to work outside Xcode.

## What Changes
- Add `xcode-build-server` integration to bridge Xcode projects with SourceKit LSP
- Add `make lsp` target to generate `buildServer.json` configuration
- Auto-generate LSP config during `make build` if missing (following Firezone's pattern)
- Add `buildServer.json` to `.gitignore` (contains machine-specific paths)
- Document LSP setup in README.md

## Impact
- Affected specs: `build-system`
- Affected code: `Makefile`, `.gitignore`, `README.md`
- No breaking changes
- Follows verified patterns from Firezone (7k stars), SweetPad, and ios-dev-starter-nvim
