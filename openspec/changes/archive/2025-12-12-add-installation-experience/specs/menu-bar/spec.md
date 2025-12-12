## MODIFIED Requirements

### Requirement: Status Item Presence

The app SHALL display a status item (icon) in the macOS menu bar when running, using a custom icon that matches the app's visual identity.

#### Scenario: App launched
- **WHEN** the app is launched
- **THEN** a custom microphone-with-cursor icon appears in the menu bar
- **AND** the icon is a template image that adapts to light and dark mode
- **AND** the icon remains visible while the app is running

#### Scenario: Icon appearance in light mode
- **WHEN** the system is in light mode
- **THEN** the menu bar icon appears as a dark silhouette

#### Scenario: Icon appearance in dark mode
- **WHEN** the system is in dark mode
- **THEN** the menu bar icon appears as a light silhouette
