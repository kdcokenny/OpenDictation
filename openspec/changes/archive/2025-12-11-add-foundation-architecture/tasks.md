# Tasks: Add Foundation Architecture

## 1. Project Setup

- [x] 1.1 Create Xcode project directory structure
- [x] 1.2 Create Package.swift with dependencies (KeyboardShortcuts, Settings, Defaults)
- [x] 1.3 Create Info.plist with LSUIElement=YES and usage descriptions
- [x] 1.4 Create OpenDictationApp.swift entry point
- [x] 1.5 Create AppDelegate.swift for menu bar management
- [ ] 1.6 Create Assets.xcassets with app icon placeholder (deferred - using system symbol)

## 2. Permissions Capability

- [x] 2.1 Create PermissionsManager.swift with ObservableObject
- [x] 2.2 Implement isAccessibilityGranted check via AXIsProcessTrusted
- [x] 2.3 Implement requestAccessibility via AXIsProcessTrustedWithOptions
- [x] 2.4 Implement isMicrophoneGranted check via AVCaptureDevice.authorizationStatus
- [x] 2.5 Implement requestMicrophone via AVCaptureDevice.requestAccess
- [x] 2.6 Implement allPermissionsGranted computed property
- [x] 2.7 Add permission polling for status updates after user grants in System Settings

## 3. Overlay Panel Capability

- [x] 3.1 Create DictationOverlayPanel.swift subclassing NSPanel
- [x] 3.2 Configure styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow]
- [x] 3.3 Override canBecomeKey to return false
- [x] 3.4 Override canBecomeMain to return false
- [x] 3.5 Set level to .floating
- [x] 3.6 Set backgroundColor to .clear and isOpaque to false
- [x] 3.7 Set collectionBehavior to [.canJoinAllSpaces, .fullScreenAuxiliary]
- [x] 3.8 Set hidesOnDeactivate to false
- [x] 3.9 Implement show(at: CGPoint) method
- [x] 3.10 Implement hide() method
- [x] 3.11 Create DictationHUDView.swift placeholder SwiftUI view

## 4. Accessibility Capability

- [x] 4.1 Create AccessibilityService.swift
- [x] 4.2 Implement getCaretPosition() -> CGPoint? function
- [x] 4.3 Create system-wide AXUIElement via AXUIElementCreateSystemWide
- [x] 4.4 Query kAXFocusedApplicationAttribute for focused app
- [x] 4.5 Query kAXFocusedUIElementAttribute for focused element
- [x] 4.6 Query kAXSelectedTextRangeAttribute for selection range
- [x] 4.7 Query kAXBoundsForRangeParameterizedAttribute for screen bounds
- [x] 4.8 Implement coordinate conversion (AX top-left to AppKit bottom-left)
- [x] 4.9 Handle nil cases gracefully (return nil when caret unavailable)

## 5. Menu Bar Capability

- [x] 5.1 Create NSStatusItem in AppDelegate.applicationDidFinishLaunching
- [x] 5.2 Set status item icon to system microphone symbol
- [x] 5.3 Create NSMenu with Settings and Quit items
- [x] 5.4 Add Cmd+, shortcut to Settings menu item
- [x] 5.5 Add Cmd+Q shortcut to Quit menu item
- [x] 5.6 Implement openSettings action (placeholder for Phase 3)
- [x] 5.7 Implement quit action via NSApp.terminate

## 6. Integration

- [x] 6.1 Wire AppDelegate to create PermissionsManager on launch
- [x] 6.2 Wire AppDelegate to create DictationOverlayPanel on launch
- [x] 6.3 Add temporary test: show overlay panel at (100, 100) on launch
- [x] 6.4 Add temporary test: show overlay panel at caret position via AccessibilityService
- [ ] 6.5 Verify panel doesn't steal focus from other apps (requires manual testing)
- [ ] 6.6 Verify panel appears on all Spaces (requires manual testing)
- [ ] 6.7 Verify panel appears over fullscreen apps (requires manual testing)

## 7. Validation

- [ ] 7.1 Test permission checks return correct values (requires manual testing)
- [ ] 7.2 Test permission requests trigger system dialogs (requires manual testing)
- [ ] 7.3 Test overlay panel behavior matches all requirements (requires manual testing)
- [ ] 7.4 Test caret detection works in TextEdit, Safari, VS Code (requires manual testing)
- [ ] 7.5 Test menu bar icon and menu functionality (requires manual testing)
- [ ] 7.6 Document any apps where caret detection fails (requires manual testing)

## Dependencies

- Tasks 2.x can run in parallel with 3.x and 4.x
- Task 6.x requires 2.x, 3.x, 4.x, and 5.x to be complete
- Task 7.x requires 6.x to be complete
