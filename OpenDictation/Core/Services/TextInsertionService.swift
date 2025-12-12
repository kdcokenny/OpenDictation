import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Result of an insertion attempt.
enum InsertionResult {
    /// Text was pasted into a text field.
    case inserted
    /// Text was copied to clipboard only (not in a text field).
    case copiedToClipboard
}

/// Service for inserting text into the focused application.
///
/// Attempts direct insertion via Accessibility API first (preferred - doesn't touch clipboard).
/// Falls back to clipboard + simulated Cmd+V paste for apps that don't support direct insertion.
/// Gracefully degrades to clipboard-only if accessibility permission is not granted.
final class TextInsertionService {
    
    private let textFieldDetector = TextFieldDetector()
    
    /// Inserts text if in a text field, otherwise copies to clipboard only.
    ///
    /// Graceful degradation: If accessibility is not granted, falls back to clipboard-only
    /// without prompting (VoiceInk pattern). User can still manually paste.
    ///
    /// - Parameter text: The text to insert or copy.
    /// - Returns: `.inserted` if pasted into text field, `.copiedToClipboard` if clipboard only.
    func insertOrCopy(_ text: String) -> InsertionResult {
        let pasteboard = NSPasteboard.general
        
        // Graceful degradation: if no accessibility permission, just copy to clipboard
        // Don't prompt - user will see "Copied to clipboard" feedback instead
        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboard
        }
        
        if textFieldDetector.isInTextField() {
            // Try Accessibility API first (doesn't touch clipboard)
            if insertViaAccessibility(text) {
                return .inserted
            }
            
            // Fall back to clipboard + paste
            let previousContents = pasteboard.string(forType: .string)
            
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            simulatePaste()
            
            // Restore previous clipboard contents after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
            
            return .inserted
        } else {
            // Not in text field: clipboard only (don't restore - user may want to paste manually)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            return .copiedToClipboard
        }
    }
    
    // MARK: - Accessibility API Insertion
    
    /// Attempts to insert text directly via Accessibility API.
    ///
    /// Sets `kAXSelectedTextAttribute` on the focused element, which inserts text
    /// at the cursor position (replacing any selection). This avoids touching the clipboard.
    ///
    /// - Parameter text: The text to insert.
    /// - Returns: `true` if insertion succeeded, `false` if it failed (caller should fall back to clipboard).
    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
        
        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }
        
        let axElement = element as! AXUIElement
        
        // Check if the element supports setting selected text
        var settableAttributes: CFArray?
        guard AXUIElementCopyAttributeNames(axElement, &settableAttributes) == .success,
              let attributes = settableAttributes as? [String],
              attributes.contains(kAXSelectedTextAttribute as String) else {
            return false
        }
        
        // Check if the attribute is actually settable
        var isSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &isSettable) == .success,
              isSettable.boolValue else {
            return false
        }
        
        // Set the selected text (inserts at cursor, or replaces selection)
        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        
        return setResult == .success
    }
    
    // MARK: - Clipboard Fallback
    
    /// Simulates pressing Cmd+V to paste.
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down for V with Cmd modifier
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        
        // Key up for V with Cmd modifier
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
