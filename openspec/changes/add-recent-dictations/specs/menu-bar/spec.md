## ADDED Requirements
### Requirement: Recent Menu Item
The status item menu SHALL include a `Recent...` item that opens the Recent dictations window.

#### Scenario: Open Recent
- **WHEN** the user clicks `Recent...`
- **THEN** the Recent window opens
- **AND** the window shows the current session's retained dictation attempts

#### Scenario: Focus existing Recent window
- **WHEN** the Recent window is already open
- **AND** the user clicks `Recent...`
- **THEN** the existing Recent window is brought to the front
