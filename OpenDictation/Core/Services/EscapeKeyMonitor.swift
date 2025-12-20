import AppKit
import CoreGraphics
import os.log

/// Singleton service that monitors for Escape key presses globally using a CGEvent tap.
///
/// This service lives for the entire app lifetime and is NOT tied to the
/// NotchOverlayPanel lifecycle. This uses a low-level CGEvent tap which allows
/// consuming events globally, preventing them from leaking to other applications.
///
/// Pattern: CGEvent tap (ghostty, Rectangle, alt-tab-macos pattern)
@MainActor
final class EscapeKeyMonitor {
    
    // MARK: - Singleton
    
    static let shared = EscapeKeyMonitor()
    
    // MARK: - Properties
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger.app(category: "EscapeKeyMonitor")
    
    /// Whether monitoring is active
    private(set) var isMonitoring = false
    
    /// Callback when Escape key is pressed. Set by AppDelegate.
    var onEscapePressed: (() -> Void)?
    
    /// Condition for when escape should be handled
    var shouldHandleEscape: (() -> Bool)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Starts monitoring for Escape key presses using a CGEvent tap.
    /// Safe to call multiple times.
    func start() {
        guard !isMonitoring else { return }
        
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        // Create event tap - requires Accessibility permissions.
        // We use .cgSessionEventTap to intercept events before other apps receive them.
        // We use .defaultTap to enable event consumption.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        ) else {
            logger.error("Failed to create CGEvent tap - missing Accessibility permissions?")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isMonitoring = true
        logger.debug("Escape key monitoring started (CGEvent tap)")
    }
    
    /// Stops monitoring for Escape key presses.
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isMonitoring = false
        logger.debug("Escape key monitoring stopped")
    }
    
    // MARK: - Private Methods
    
    /// C-style static callback required by CGEvent.tapCreate.
    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, cgEvent, userInfo in
        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // Get our monitor instance back from the opaque pointer
        let monitor = Unmanaged<EscapeKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        
        // Only handle keyDown events
        guard type == .keyDown else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // Check for Escape key (keyCode 53)
        let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 53 else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // Check if we should handle this escape (delegated to AppDelegate)
        guard monitor.shouldHandleEscape?() == true else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        monitor.logger.debug("Escape key pressed - consuming event")
        
        // Notify of the escape press - must be done on main thread for Swift concurrency safety
        DispatchQueue.main.async {
            monitor.onEscapePressed?()
        }
        
        // Return nil to consume the event, preventing it from bleeding through to other apps
        return nil
    }
}

