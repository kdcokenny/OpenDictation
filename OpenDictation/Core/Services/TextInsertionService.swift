import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os.log

/// Result of attempting to deliver transcribed text to the user.
enum TextDeliveryResult: Equatable {
    case inserted
    case copiedOnly
    case failed(String)
}

/// Service for inserting text into the focused application via Universal Paste.
///
/// Implements the "Always Paste" strategy with Apple-quality hardening:
/// 1. Save current clipboard state (all types, not just string)
/// 2. Set text to clipboard with multi-tier changeCount verification
/// 3. Simulate Cmd+V via CGEvent with explicit key events
/// 4. Restore previous clipboard state after a bounded delay
///
/// Hardening techniques from industry analysis:
/// - `.combinedSessionState` for proper event coordination
/// - 3-attempt retry loop for clipboard writes with escalating delays
/// - changeCount polling (200ms timeout) for asynchronous commitment verification
/// - Full pasteboard preservation (all types)
/// - Concurrency lock to prevent overlapping operations
/// - Event source suppression to prevent input interference
/// - Explicit Command key events for maximum app compatibility
@MainActor
final class TextInsertionService {
    
    private let logger = Logger(subsystem: "com.opendictation", category: "TextInsertionService")
    private let accessibilityChecker: AccessibilityChecker
    private let pasteSimulator: (() -> Bool)?
    private let clipboardRestoreDelay: Duration
    
    // MARK: - Concurrency Control
    
    /// Lock protecting insertion state to prevent concurrent paste operations
    private static let insertionLock = NSLock()
    
    /// Flag indicating if a paste operation is in progress
    private static var isInserting = false
    
    // MARK: - Deferred Clipboard Restoration
    
    /// Saved pasteboard contents pending restoration (set after successful paste)
    private var pendingRestore: SavedPasteboardContents?
    
    /// Pasteboard generation written by this service. Any later write belongs to
    /// the user or another app, even when it contains the same text.
    private var insertedPasteboardChangeCount: Int?

    /// Fallback restoration that does not depend on overlay availability or dismissal.
    private var clipboardRestoreTask: Task<Void, Never>?
    
    /// Saved pasteboard contents for restoration
    private struct SavedPasteboardContents {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }
    
    // MARK: - Lifecycle
    
    init(
        accessibilityChecker: AccessibilityChecker = SystemAccessibilityChecker(),
        pasteSimulator: (() -> Bool)? = nil,
        clipboardRestoreDelay: Duration = .seconds(2)
    ) {
        self.accessibilityChecker = accessibilityChecker
        self.pasteSimulator = pasteSimulator
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }
    
    // MARK: - Public API
    
    /// Inserts text using the universal paste method.
    ///
    /// - Parameter text: The text to insert.
    /// - Returns: A delivery result describing whether text was pasted, copied, or failed.
    func insertText(_ text: String) -> TextDeliveryResult {
        // A new delivery must not replace restoration state from an earlier paste.
        restoreClipboard()

        // Acquire lock and check for concurrent operation
        Self.insertionLock.lock()
        
        guard !Self.isInserting else {
            Self.insertionLock.unlock()
            logger.warning("Paste operation already in progress, rejecting concurrent call")
            return .failed("Paste operation already in progress.")
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
        
        let canPaste = accessibilityChecker.isAccessibilityGranted
        let savedContents = savePasteboardContents(pasteboard)
        let insertedChangeCount: Int

        switch writeAndVerifyText(text, to: pasteboard) {
        case .verified(let changeCount):
            insertedChangeCount = changeCount
        case .ownershipChanged:
            return .failed("Clipboard changed before paste. Try again.")
        case .failed(let changeCount):
            restorePasteboardContents(savedContents, to: pasteboard, ifUnchangedSince: changeCount)
            return .failed(canPaste ? "Failed to verify clipboard content." : "Failed to copy text to clipboard.")
        }

        guard canPaste else {
            logger.warning("Accessibility permission missing - falling back to clipboard copy")
            return .copiedOnly
        }
        guard pasteboard.changeCount == insertedChangeCount else {
            return .failed("Clipboard changed before paste. Try again.")
        }

        guard simulatePaste() else {
            logger.error("Failed to simulate paste")
            restorePasteboardContents(savedContents, to: pasteboard, ifUnchangedSince: insertedChangeCount)
            return .failed("Failed to simulate paste.")
        }

        // Keep the generation returned by our write. Reading it again here could
        // mistake another app's copy for our own and restore over that newer data.
        pendingRestore = savedContents
        insertedPasteboardChangeCount = insertedChangeCount
        scheduleClipboardRestore()
        return .inserted
    }
    
    /// Restores the clipboard to its previous state after a successful paste.
    ///
    /// The overlay may call this after dismissal. A fallback task calls it when no
    /// overlay exists, so clipboard cleanup never depends on UI lifecycle.
    func restoreClipboard() {
        clipboardRestoreTask?.cancel()
        clipboardRestoreTask = nil

        guard let savedContents = pendingRestore else {
            insertedPasteboardChangeCount = nil
            return
        }

        let expectedChangeCount = insertedPasteboardChangeCount
        pendingRestore = nil
        insertedPasteboardChangeCount = nil

        let pasteboard = NSPasteboard.general
        
        // changeCount identifies writes, so copying identical text still protects the
        // user's newer clipboard contents from restoration.
        if let expectedChangeCount,
           pasteboard.changeCount == expectedChangeCount {
            restorePasteboardContents(savedContents, to: pasteboard)
            logger.debug("Clipboard restored after paste")
        } else {
            logger.debug("Clipboard changed since paste, skipping restore")
        }
    }
    
    // MARK: - Private Helpers

    private func scheduleClipboardRestore() {
        clipboardRestoreTask?.cancel()
        let delay = clipboardRestoreDelay

        clipboardRestoreTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            self?.restoreClipboard()
        }
    }
    
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
        
        if !pasteboard.writeObjects(pasteboardItems) {
            logger.warning("Failed to restore clipboard contents.")
        }
    }
    
    private func restorePasteboardContents(
        _ saved: SavedPasteboardContents,
        to pasteboard: NSPasteboard,
        ifUnchangedSince changeCount: Int
    ) {
        guard pasteboard.changeCount == changeCount else { return }
        restorePasteboardContents(saved, to: pasteboard)
    }

    /// Simulates pressing Cmd+V to paste with explicit key events.
    ///
    /// Uses `.combinedSessionState` for proper event coordination and
    /// posts 4 explicit events (Cmd down, V down, V up, Cmd up) for
    /// maximum app compatibility.
    private func simulatePaste() -> Bool {
        if let pasteSimulator {
            return pasteSimulator()
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create event source")
            return false
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
            return false
        }
        
        // Set Command flag on V events for apps that check flags
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        
        // Post events in sequence: Cmd↓ → V↓ → V↑ → Cmd↑
        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        return true
    }
    
    // MARK: - Bulletproof Verification Helpers

    private enum ClipboardWriteResult {
        case verified(changeCount: Int)
        case failed(changeCount: Int)
        case ownershipChanged
    }

    private func writeAndVerifyText(_ text: String, to pasteboard: NSPasteboard) -> ClipboardWriteResult {
        let maxAttempts = 3
        var ownedChangeCount: Int?

        for attempt in 1...maxAttempts {
            if attempt > 1 {
                let delay = Double(attempt - 1) * 0.05 // 50ms, 100ms
                logger.info("Clipboard write retry \(attempt) after \(delay)s delay")
                Thread.sleep(forTimeInterval: delay)
            }
            if let ownedChangeCount, pasteboard.changeCount != ownedChangeCount {
                return .ownershipChanged
            }

            // clearContents returns the generation at the moment we take ownership.
            // Never substitute a later read, which may belong to another app.
            let changeCount = pasteboard.clearContents()
            ownedChangeCount = changeCount
            guard pasteboard.setString(text, forType: .string) else {
                logger.warning("Clipboard write failed on attempt \(attempt)/\(maxAttempts)")
                continue
            }

            let committed = waitForClipboardCommit(
                pasteboard: pasteboard,
                expectedChangeCount: changeCount,
                timeout: 0.2
            )
            guard pasteboard.changeCount == changeCount else { return .ownershipChanged }
            let verified = committed && verifyClipboardContent(pasteboard: pasteboard, expected: text)
            guard pasteboard.changeCount == changeCount else { return .ownershipChanged }
            if verified {
                return .verified(changeCount: changeCount)
            }

            logger.warning("Clipboard verification failed on attempt \(attempt)/\(maxAttempts)")
        }

        // The loop always attempts a write before reaching this point.
        guard let ownedChangeCount else { preconditionFailure("No clipboard write attempted") }
        return .failed(changeCount: ownedChangeCount)
    }
    
    /// Polls until pasteboard.changeCount reaches expected value.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard to monitor.
    ///   - expectedChangeCount: The count we're waiting for.
    ///   - timeout: Maximum time to wait in seconds.
    private func waitForClipboardCommit(
        pasteboard: NSPasteboard,
        expectedChangeCount: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let pollInterval: TimeInterval = 0.005 // 5ms polling
        
        while Date() < deadline {
            if pasteboard.changeCount >= expectedChangeCount {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        
        return false
    }
    
    /// Verifies clipboard content matches expected text with multiple retries.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard to check.
    ///   - expected: The text we expect to find.
    ///   - maxRetries: Number of attempts before giving up.
    private func verifyClipboardContent(
        pasteboard: NSPasteboard,
        expected: String,
        maxRetries: Int = 3
    ) -> Bool {
        for attempt in 1...maxRetries {
            if let current = pasteboard.string(forType: .string), current == expected {
                return true
            }
            
            if attempt < maxRetries {
                // Short wait before retry to let system state settle
                Thread.sleep(forTimeInterval: 0.01) // 10ms
            }
        }
        
        let actual = pasteboard.string(forType: .string) ?? "<nil>"
        logger.error("Clipboard verification failed after \(maxRetries) retries. Expected length: \(expected.count), Actual length: \(actual.count)")
        return false
    }
}
