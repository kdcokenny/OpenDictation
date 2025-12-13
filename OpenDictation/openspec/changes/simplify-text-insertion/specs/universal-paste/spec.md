# Universal Paste Requirement

## MODIFIED Requirements

### Requirement: Universal Paste Strategy
The system SHALL use a universal paste mechanism for text insertion to ensure reliability across all applications.

#### Scenario: Always Paste
Given the user has dictated text
When the transcription completes
Then the system MUST attempt to insert the text using the Clipboard + Paste (Cmd+V) method
And the system MUST NOT check if a text field is currently focused
And the system MUST save the previous clipboard content before pasting
And the system MUST restore the previous clipboard content after a short delay (e.g., 150ms)

### Requirement: Permissions Handling
The system SHALL handle cases where accessibility permissions are missing by gracefully falling back to clipboard copy.

#### Scenario: Missing Permissions
Given the app does not have Accessibility permissions (`AXIsProcessTrusted` returns false)
When the system attempts to insert text
Then it MUST fall back to "Copy to Clipboard" only
And it MUST NOT attempt to simulate key presses (which would fail)
And it MUST return a result indicating the fallback occurred

## REMOVED Requirements

### Requirement: Detection Logic
The `TextFieldDetector` component is unreliable and SHALL be removed.

#### Scenario: Detection Removal
The system NO LONGER needs to detect if the focused element is a text field. The `TextFieldDetector` component should be removed as detection is notoriously unreliable and unnecessary for the universal paste strategy.

### Requirement: Accessibility Insertion Logic
Direct accessibility API insertion SHALL be removed in favor of clipboard simulation.

#### Scenario: AX Insertion Removal
The system NO LONGER attempts to insert text using the Accessibility API (`kAXSelectedTextAttribute`). This method is removed in favor of the universal paste approach which works more reliably across all app types.
