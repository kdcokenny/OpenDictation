# accessibility Specification

## Purpose
TBD - created by archiving change add-foundation-architecture. Update Purpose after archive.
## Requirements
### Requirement: Get Caret Position

The system SHALL provide a function to get the screen coordinates of the text caret in the currently focused application using the Accessibility API.

#### Scenario: Caret in text field
- **WHEN** the user has focus in a text field
- **AND** `getCaretPosition()` is called
- **THEN** it returns the screen coordinates (CGPoint) of the text cursor
- **AND** the coordinates are in AppKit coordinate space (origin at bottom-left of screen)

#### Scenario: No text field focused
- **WHEN** the user has focus on a non-text element (e.g., a button)
- **AND** `getCaretPosition()` is called
- **THEN** it returns `nil`

#### Scenario: App doesn't expose caret
- **WHEN** the focused application doesn't expose `kAXSelectedTextRangeAttribute`
- **AND** `getCaretPosition()` is called
- **THEN** it returns `nil`

### Requirement: System-Wide Element Access

The system SHALL use `AXUIElementCreateSystemWide()` as the entry point for accessibility queries.

#### Scenario: Query system-wide element
- **WHEN** `getCaretPosition()` is called
- **THEN** it creates a system-wide AXUIElement
- **AND** queries `kAXFocusedApplicationAttribute` to get the focused app

### Requirement: Focused Application Detection

The system SHALL retrieve the currently focused application via `kAXFocusedApplicationAttribute`.

#### Scenario: Focused app retrieved
- **WHEN** Safari is the frontmost application
- **AND** the focused application is queried
- **THEN** the Safari application's AXUIElement is returned

### Requirement: Focused Element Detection

The system SHALL retrieve the currently focused UI element via `kAXFocusedUIElementAttribute`.

#### Scenario: Focused element retrieved
- **WHEN** the user has focus in a search field in Safari
- **AND** the focused element is queried
- **THEN** the search field's AXUIElement is returned

### Requirement: Selection Range Query

The system SHALL query `kAXSelectedTextRangeAttribute` to get the current text selection/cursor position as a CFRange.

#### Scenario: Cursor at position 5
- **WHEN** the text cursor is at character position 5 with no selection
- **AND** `kAXSelectedTextRangeAttribute` is queried
- **THEN** a CFRange with location=5 and length=0 is returned

#### Scenario: Text selected
- **WHEN** characters 5-10 are selected
- **AND** `kAXSelectedTextRangeAttribute` is queried
- **THEN** a CFRange with location=5 and length=5 is returned

### Requirement: Bounds for Range Query

The system SHALL query `kAXBoundsForRangeParameterizedAttribute` to convert a text range to screen coordinates.

#### Scenario: Get bounds for cursor
- **WHEN** a valid selection range is obtained
- **AND** `kAXBoundsForRangeParameterizedAttribute` is queried with that range
- **THEN** a CGRect representing the screen position of that range is returned

### Requirement: Coordinate Conversion

The system SHALL convert coordinates from Accessibility API format (top-left origin) to AppKit format (bottom-left origin).

#### Scenario: Convert coordinates
- **WHEN** the Accessibility API returns a rect at (100, 50) on a 1000px tall screen
- **THEN** the converted AppKit coordinate is (100, 950)

