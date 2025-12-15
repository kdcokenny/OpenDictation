import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os.log

/// Service for inserting text into the focused application via Universal Paste.
///
/// Implements the "Always Paste" strategy with Apple-quality hardening:
/// 1. Save current clipboard state (all types, not just string)
/// 2. Set text to clipboard with verification
/// 3. Simulate Cmd+V via CGEvent with explicit key events
/// 4. Restore previous clipboard state after synchronous delay
///
/// Hardening techniques from industry analysis:
/// - `.combinedSessionState` for proper event coordination
/// - 50ms clipboard stabilization delay before paste
/// - 150ms synchronous delay for paste completion
/// - Full pasteboard preservation (all types)
/// - Concurrency lock to prevent overlapping operations
/// - Event source suppression to prevent input interference
/// - Explicit Command key events for maximum app compatibility
@MainActor
final class TextInsertionService {
    
    private let logger = Logger(subsystem: "com.opendictation", category: "TextInsertionService")
    
    // MARK: - Concurrency Control
    
    /// Lock protecting insertion state to prevent concurrent paste operations
    private static let insertionLock = NSLock()
    
    /// Flag indicating if a paste operation is in progress
    private static var isInserting = false
    
    // MARK: - Saved Clipboard State
    
    /// Saved pasteboard contents for restoration
    private struct SavedPasteboardContents {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }
    
    // MARK: - Public API
    
    /// Inserts text using the universal paste method.
    ///
    /// - Parameter text: The text to insert.
    /// - Returns: `true` if text was sent to clipboard and paste was attempted.
    func insertText(_ text: String) -> Bool {
        // Acquire lock and check for concurrent operation
        Self.insertionLock.lock()
        
        guard !Self.isInserting else {
            Self.insertionLock.unlock()
            logger.warning("Paste operation already in progress, rejecting concurrent call")
            return false
        }
        
        Self.isInserting = true
        Self.insertionLock.unlock()
        
        // Ensure flag is always reset on exit
        defer {
            Self.insertionLock.lock()
            Self.isInserting = false
            Self.insertionLock.unlock()
        }
        
        let pasteboard = NSPasteboard.general
        
        // 1. Guard: Check Accessibility Permissions
        // CGEvent requires AXIsProcessTrusted to post events to other apps.
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility permission missing - falling back to clipboard copy")
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return false // Indicates fallback to clipboard-only (no paste attempted)
        }
        
        // 2. Save previous clipboard contents (all types)
        let savedContents = savePasteboardContents(pasteboard)
        
        // 3. Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 4. Verify clipboard content was set correctly
        guard pasteboard.string(forType: .string) == text else {
            logger.error("Clipboard content not set correctly - aborting paste")
            restorePasteboardContents(savedContents, to: pasteboard)
            return false
        }
        
        // 5. Wait for clipboard to stabilize (50ms)
        Thread.sleep(forTimeInterval: 0.05)
        
        // 6. Simulate Cmd+V
        simulatePaste()
        
        // 7. Wait synchronously for paste to complete (150ms)
        Thread.sleep(forTimeInterval: 0.15)
        
        // 8. Restore clipboard if it still contains our text
        // (avoids overwriting if user copied something else)
        if let current = pasteboard.string(forType: .string), current == text {
            restorePasteboardContents(savedContents, to: pasteboard)
            logger.debug("Clipboard restored")
        }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    /// Saves all pasteboard contents for later restoration.
    ///
    /// Captures all types and data from all pasteboard items to ensure
    /// non-text content (images, URLs, files) is preserved.
    private func savePasteboardContents(_ pasteboard: NSPasteboard) -> SavedPasteboardContents {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        
        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            if !itemData.isEmpty {
                items.append(itemData)
            }
        }
        
        return SavedPasteboardContents(items: items)
    }
    
    /// Restores previously saved pasteboard contents.
    ///
    /// Writes back all saved types and data to preserve the user's
    /// original clipboard content.
    private func restorePasteboardContents(_ saved: SavedPasteboardContents, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        
        if saved.items.isEmpty {
            // Original clipboard was empty
            logger.debug("Clipboard cleared (restored to empty)")
            return
        }
        
        // Create pasteboard items for each saved item
        var pasteboardItems: [NSPasteboardItem] = []
        for itemData in saved.items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboardItems.append(item)
        }
        
        pasteboard.writeObjects(pasteboardItems)
    }
    
    /// Simulates pressing Cmd+V to paste with explicit key events.
    ///
    /// Uses `.combinedSessionState` for proper event coordination and
    /// posts 4 explicit events (Cmd down, V down, V up, Cmd up) for
    /// maximum app compatibility.
    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create event source")
            return
        }
        
        // Configure event source to suppress user keyboard input during paste
        // This prevents user typing from interfering with the paste operation
        // Mouse and system events (volume, brightness) are still permitted
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        
        let cmdKeyCode = CGKeyCode(kVK_Command)
        let vKeyCode = CGKeyCode(kVK_ANSI_V)
        
        // Create all 4 events for explicit Command+V sequence
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            logger.error("Failed to create paste events")
            return
        }
        
        // Set Command flag on V events for apps that check flags
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        
        // Post events in sequence: Cmd↓ → V↓ → V↑ → Cmd↑
        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
    }
}
