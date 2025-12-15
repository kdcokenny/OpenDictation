# Tasks: Add LSP Support

## 1. Implementation
- [x] 1.1 Add `lsp` target to Makefile with graceful fallback if xcode-build-server not installed
- [x] 1.2 Update `build` target to auto-generate buildServer.json if missing
- [x] 1.3 Add `buildServer.json` to `.gitignore`
- [x] 1.4 Remove `-derivedDataPath` from Makefile to use system DerivedData (matches Firezone pattern)
- [x] 1.5 Add `.sourcekit-lsp/config.json` with `defaultWorkspaceType: buildServer`

## 2. Documentation
- [x] 2.1 Create CONTRIBUTING.md with build and LSP setup instructions
- [x] 2.2 Update README.md to link to CONTRIBUTING.md instead of inline dev docs
- [x] 2.3 Document requirement to build in Xcode GUI for LSP to work

## 3. Verification
- [x] 3.1 Install xcode-build-server (`brew install xcode-build-server`)
- [x] 3.2 Run `make lsp` and verify buildServer.json is created
- [x] 3.3 Run `make build` and verify build succeeds
- [x] 3.4 Build in Xcode GUI and verify SourceKit LSP errors are resolved in Zed
