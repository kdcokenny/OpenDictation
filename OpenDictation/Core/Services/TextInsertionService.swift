import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os.log

/// Service for inserting text into the focused application via Universal Paste.
///
/// Implements the "Always Paste" strategy:
/// 1. Save current clipboard state
/// 2. Set text to clipboard
/// 3. Simulate Cmd+V via CGEvent
/// 4. Restore previous clipboard state after a delay
@MainActor
final class TextInsertionService {
    
    private let logger = Logger(subsystem: "com.opendictation", category: "TextInsertionService")
    
    /// Inserts text using the universal paste method.
    ///
    /// - Parameter text: The text to insert.
    /// - Returns: `true` if text was sent to clipboard and paste was attempted.
    func insertText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        // 1. Guard: Check Accessibility Permissions
        // CGEvent requires AXIsProcessTrusted to post events to other apps.
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility permission missing - falling back to clipboard copy")
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return false // Indicates fallback to clipboard-only (no paste attempted)
        }
        
        // 2. Save previous clipboard contents
        let previousString = pasteboard.string(forType: .string)
        // Note: For a more robust implementation, we could save all pasteboard items,
        // but saving the string is usually sufficient for text-heavy workflows.
        
        // 3. Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 4. Simulate Cmd+V
        simulatePaste()
        
        // 5. Restore clipboard after delay
        // 150ms is generally sufficient for modern macOS apps to handle the paste event
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            // Only restore if the clipboard still contains our inserted text
            // (avoids overwriting if user copied something else in the split second)
            guard let self = self else { return }
            
            if let current = pasteboard.string(forType: .string), current == text {
                if let previous = previousString {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                    self.logger.debug("Clipboard restored")
                } else {
                    // If previous was empty or non-string, just clear
                    pasteboard.clearContents()
                    self.logger.debug("Clipboard cleared (restored to empty)")
                }
            }
        }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    /// Simulates pressing Cmd+V to paste.
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down: Cmd + V
        let vKeyCode = CGKeyCode(kVK_ANSI_V)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            logger.error("Failed to create paste events")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

