import AppKit
import AppKit
import SwiftUI
import CoreGraphics

/// A notch-based overlay panel that displays the dictation UI.
///
/// This panel is designed to:
/// - Expand horizontally from the hardware notch during recording
/// - Float above all windows without stealing focus
/// - Appear on all Spaces and work with fullscreen apps
/// - Handle Escape key via global monitor to cancel dictation
///

@MainActor
final class NotchOverlayPanel {
    
    // MARK: - Constants
    
    /// Duration to show success/clipboard state before dismissing.
    private static let successDisplayDuration: TimeInterval = 0.4
    
    /// Duration to show error state before dismissing.
    private static let errorDisplayDuration: TimeInterval = 0.5
    
    /// Duration to wait after shake before dismissing.
    private static let shakeCompleteDuration: TimeInterval = 0.6
    
    // MARK: - Properties
    
    private var window: NotchWindow?
    private var hostingView: NSHostingView<NotchDictationView>?
    private let viewModel = NotchViewModel()
    private let screen: NSScreen
    
    /// Event monitor for Escape key.
    private var escapeMonitor: EventMonitor?
    
    /// Callback when escape key is pressed.
    var onEscapePressed: (() -> Void)?
    
    /// Callback when dismiss animation completes.
    var onDismissCompleted: (() -> Void)?
    
    /// Flag to prevent multiple dismiss calls.
    private var isDismissing = false
    
    // MARK: - Initialization
    
    /// Creates a notch overlay panel for the given screen.
    /// - Parameter screen: The screen with a hardware notch.
    init(screen: NSScreen) {
        self.screen = screen
        // Configure viewModel with hardware notch size (mew-notch pattern)
        viewModel.configure(hardwareNotchSize: screen.notchSize)
    }
    
    // MARK: - Public Methods
    
    /// Shows the panel with expand animation.
    func show() {
        isDismissing = false
        viewModel.setVisualState(.recording)
        
        // Create window if needed
        if window == nil {
            createWindow()
        }
        
        // Start escape monitors
        startEscapeMonitors()
        
        // Show window (collapsed initially) - use orderFrontRegardless to avoid focus stealing
        window?.orderFrontRegardless()
        
        // Apply 100ms render delay before expanding (NotchDrop pattern)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchWindow.renderDelay) { [weak self] in
            self?.viewModel.expand()
        }
    }
    
    /// Updates the visual state of the panel.
    func setVisualState(_ state: NotchVisualState) {
        viewModel.setVisualState(state)
    }
    
    /// Updates the audio level for waveform visualization.
    /// - Parameter level: Audio level from 0.0 (silent) to 1.0 (max).
    func setAudioLevel(_ level: Float) {
        viewModel.setAudioLevel(level)
    }
    
    /// Hides the panel with collapse animation.
    func hide() {
        guard !isDismissing else { return }
        isDismissing = true
        
        stopEscapeMonitors()
        viewModel.collapse()
        
        // Wait for animation to complete before hiding window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.window?.orderOut(nil)
            self?.onDismissCompleted?()
            self?.isDismissing = false
        }
    }
    
    /// Shows success state, waits briefly, then dismisses.
    func showSuccessAndDismiss() {
        viewModel.setVisualState(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successDisplayDuration) { [weak self] in
            self?.hide()
        }
    }
    
    /// Shows clipboard state, waits briefly, then dismisses.
    func showClipboardAndDismiss() {
        viewModel.setVisualState(.copiedToClipboard)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successDisplayDuration) { [weak self] in
            self?.hide()
        }
    }
    
    /// Shows error state, waits, then dismisses.
    func showErrorAndDismiss() {
        viewModel.setVisualState(.error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorDisplayDuration) { [weak self] in
            self?.hide()
        }
    }
    
    /// Shows empty state (shake), waits, then dismisses.
    func showEmptyAndDismiss() {
        viewModel.setVisualState(.empty)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shakeCompleteDuration) { [weak self] in
            self?.hide()
        }
    }
    
    // MARK: - Private Methods
    
    /// Creates the NotchWindow and sets up the SwiftUI content.
    private func createWindow() {
        let notchWindow = NotchWindow(screen: screen)
        
        // Create SwiftUI view (viewModel already configured with notchSize)
        let dictationView = NotchDictationView(viewModel: viewModel)
        
        let hosting = NSHostingView(rootView: dictationView)
        hosting.frame = notchWindow.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        
        notchWindow.contentView = hosting
        
        self.window = notchWindow
        self.hostingView = hosting
    }
    
    /// Start monitoring for Escape key globally and locally.
    private func startEscapeMonitors() {
        // Ensure clean state
        stopEscapeMonitors()
        
        escapeMonitor = EventMonitor(
            mask: NSEvent.EventTypeMask.keyDown,
            handler: { [weak self] (event: NSEvent) in
                // Check for Escape key (53) and if window is visible
                let isEscape = event.keyCode == 53
                if isEscape && self?.window?.isVisible == true {
                    DispatchQueue.main.async {
                        self?.onEscapePressed?()
                    }
                }
            },
            shouldConsume: { [weak self] event in
                // Consume escape key when panel is visible
                return event.keyCode == 53 && self?.window?.isVisible == true
            }
        )
        escapeMonitor?.start()
    }
    
    /// Stop monitoring for Escape key.
    private func stopEscapeMonitors() {
        escapeMonitor?.stop()
        escapeMonitor = nil
    }
}

/// C-function callback for the event tap
private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refCon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refCon = refCon else { return Unmanaged.passUnretained(event) }
    
    let monitor = Unmanaged<EventMonitor>.fromOpaque(refCon).takeUnretainedValue()
    
    // Check if we should consume
    if monitor.shouldConsume?(NSEvent(cgEvent: event)!) == true {
        // Also trigger handler before consuming
        monitor.handler(NSEvent(cgEvent: event)!)
        return nil
    }
    
    // Always trigger handler for monitoring purposes if not consumed above?
    // The previous implementation both handled AND potentially consumed.
    // Let's stick to the pattern:
    // If consumed, we return nil (and still trigger handler implicitly inside the check or explicitly).
    // The original logic was: call handler, then check consumption.
    
    monitor.handler(NSEvent(cgEvent: event)!)
    return Unmanaged.passUnretained(event)
}

/// Monitors keyboard/mouse events via CGEventTap to allow global consumption.
final class EventMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let mask: NSEvent.EventTypeMask
    
    // Internal access for callback
    let handler: (NSEvent) -> Void
    let shouldConsume: ((NSEvent) -> Bool)?

    init(
        mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void,
        shouldConsume: ((NSEvent) -> Bool)? = nil
    ) {
        self.mask = mask
        self.handler = handler
        self.shouldConsume = shouldConsume
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        
        // Convert NSEventMask to CGEventMask (approximate for keyDown)
        // For now hardcoded to .keyDown (1 << 10) as that's what we use.
        // CGEventMask is bitfield. kCGEventKeyDown = 10.
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Create the tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap - permission missing?")
            return
        }
        
        self.eventTap = tap
        
        // Create run loop source
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("Failed to create run loop source")
            return
        }
        
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // CFMachPortInvalidate(tap) // Not strictly necessary for CFMachPort but good practice? 
            // ARC handles the release of the object.
            eventTap = nil
        }
    }
}
