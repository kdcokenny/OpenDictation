## ADDED Requirements

### Requirement: LSP Support for Non-Xcode Editors
The project SHALL support SourceKit LSP integration for developers using non-Xcode editors (VSCode, Cursor, Neovim, etc.) via xcode-build-server.

#### Scenario: Generate LSP configuration
- **WHEN** developer runs `make lsp`
- **THEN** xcode-build-server generates a `buildServer.json` file in the project root
- **AND** the configuration points to the correct Xcode project and scheme
- **AND** if xcode-build-server is not installed, a helpful error message is displayed

#### Scenario: Auto-generate LSP config during build
- **WHEN** developer runs `make build` without a `buildServer.json` file
- **THEN** the build process automatically runs `make lsp` first
- **AND** then proceeds with the normal build

#### Scenario: LSP configuration not committed
- **WHEN** developer generates `buildServer.json`
- **THEN** the file is ignored by git (listed in `.gitignore`)
- **AND** each developer generates their own local configuration

#### Scenario: SourceKit LSP resolves project types
- **WHEN** developer opens a Swift file in a non-Xcode editor with sourcekit-lsp
- **AND** `buildServer.json` exists
- **AND** the project has been built at least once
- **THEN** the editor correctly resolves types from other project files
- **AND** the editor correctly resolves types from Swift Package dependencies
