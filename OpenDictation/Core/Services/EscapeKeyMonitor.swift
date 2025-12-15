import AppKit
import os.log

/// Singleton service that monitors for Escape key presses globally.
///
/// This service lives for the entire app lifetime and is NOT tied to the
/// NotchOverlayPanel lifecycle. This follows NotchDrop's pattern of keeping
/// event monitors separate from UI components to survive screen changes.
///
/// Pattern: Singleton event monitor (NotchDrop's EventMonitors class)
@MainActor
final class EscapeKeyMonitor {
    
    // MARK: - Singleton
    
    static let shared = EscapeKeyMonitor()
    
    // MARK: - Properties
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let logger = Logger(subsystem: "com.opendictation", category: "EscapeKeyMonitor")
    
    /// Whether monitoring is active
    private(set) var isMonitoring = false
    
    /// Callback when Escape key is pressed. Set by AppDelegate.
    var onEscapePressed: (() -> Void)?
    
    /// Condition for when escape should be handled
    var shouldHandleEscape: (() -> Bool)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Starts monitoring for Escape key presses.
    /// Safe to call multiple times (will not create duplicate monitors).
    func start() {
        guard !isMonitoring else { return }
        
        // Global monitor for when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Local monitor for when app is focused (and to consume the event)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil  // Consume the event
            }
            return event
        }
        
        isMonitoring = true
        logger.debug("Escape key monitoring started")
    }
    
    /// Stops monitoring for Escape key presses.
    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isMonitoring = false
        logger.debug("Escape key monitoring stopped")
    }
    
    // MARK: - Private Methods
    
    /// Handles a key event. Returns true if the event was consumed.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for Escape key (keyCode 53)
        guard event.keyCode == 53 else { return false }
        
        // Check if we should handle this escape
        guard shouldHandleEscape?() == true else { return false }
        
        logger.debug("Escape key pressed")
        
        DispatchQueue.main.async { [weak self] in
            self?.onEscapePressed?()
        }
        
        return true
    }
}
