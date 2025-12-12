import AppKit
import SwiftUI

/// A non-activating floating panel that displays the dictation HUD.
///
/// This panel is designed to:
/// - Float above all windows without stealing focus
/// - Appear at fixed bottom-center position (~60px from bottom)
/// - Appear on all Spaces
/// - Work with fullscreen apps
/// - Handle Escape key to cancel dictation
final class DictationOverlayPanel: NSPanel {

    // MARK: - Constants

    private static let panelWidth: CGFloat = DictationHUDView.totalWidth
    private static let panelHeight: CGFloat = DictationHUDView.totalHeight
    private static let bottomMargin: CGFloat = 10
    
    /// Duration to show success/clipboard state before dismissing
    private static let successDisplayDuration: TimeInterval = 0.4
    
    /// Duration to show error state before dismissing
    private static let errorDisplayDuration: TimeInterval = 0.5
    
    /// Duration to wait after shake before dismissing
    private static let shakeCompleteDuration: TimeInterval = 0.6

    // MARK: - Properties

    private var hudState = HUDState()
    private var hostingView: NSHostingView<DictationHUDView>!
    
    /// Global event monitor for Escape key (needed because nonactivatingPanel doesn't become key)
    /// Marked nonisolated(unsafe) to allow cleanup in deinit - safe because NSEvent monitor APIs are thread-safe
    private nonisolated(unsafe) var escapeMonitor: Any?
    
    /// Callback when escape key is pressed
    var onEscapePressed: (() -> Void)?
    
    /// Callback when dismiss animation completes
    var onDismissCompleted: (() -> Void)?

    // MARK: - Initialization

    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: Self.panelWidth,
            height: Self.panelHeight
        )

        super.init(
            contentRect: initialFrame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.hostingView = NSHostingView(rootView: DictationHUDView(state: hudState))

        configurePanel()
        setupContentView()
    }
    
    deinit {
        // Direct cleanup since escapeMonitor is nonisolated(unsafe)
        // NSEvent.removeMonitor is thread-safe
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - NSPanel Overrides

    override var canBecomeKey: Bool {
        // Allow becoming key to receive escape key events
        true
    }

    override var canBecomeMain: Bool {
        false
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onEscapePressed?()
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func cancelOperation(_ sender: Any?) {
        // Also handle cancelOperation (another way Escape can be delivered)
        onEscapePressed?()
    }

    // MARK: - Public Methods

    /// Shows the panel at fixed bottom-center position with appear animation.
    func show() {
        hudState.visualState = .recording
        positionAtBottomCenter()
        
        // Start global escape monitor (panel doesn't become key, so we need this)
        startEscapeMonitor()
        
        // Start invisible, then animate in
        hudState.isVisible = false
        orderFrontRegardless()
        
        // Brief delay to ensure view is ready, then animate
        DispatchQueue.main.async { [weak self] in
            self?.hudState.isVisible = true
        }
    }

    /// Updates the visual state of the HUD.
    func setVisualState(_ state: HUDVisualState) {
        hudState.visualState = state
    }
    
    /// Updates the audio level for waveform visualization.
    /// - Parameter level: Audio level from 0.0 (silent) to 1.0 (max).
    func setAudioLevel(_ level: Float) {
        hudState.audioLevel = level
    }

    /// Hides the panel with dismiss animation.
    func hide() {
        // Stop escape monitor
        stopEscapeMonitor()
        
        hudState.isVisible = false
        
        // Wait for animation to complete before actually hiding
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.orderOut(nil)
            self?.onDismissCompleted?()
        }
    }
    
    /// Shows success state (checkmark), waits briefly, then dismisses.
    func showSuccessAndDismiss() {
        hudState.visualState = .success
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successDisplayDuration) { [weak self] in
            self?.hide()
        }
    }
    
    /// Shows clipboard state, waits briefly, then dismisses.
    func showClipboardAndDismiss() {
        hudState.visualState = .copiedToClipboard
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successDisplayDuration) { [weak self] in
            self?.hide()
        }
    }
    
    /// Shows error state, waits, then dismisses.
    /// Note: Error sound is played by AudioFeedbackService in AppDelegate.
    func showErrorAndDismiss() {
        hudState.visualState = .error
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorDisplayDuration) { [weak self] in
            self?.hide()
        }
    }
    
    /// Shows empty state (shake), waits, then dismisses.
    func showEmptyAndDismiss() {
        hudState.visualState = .empty
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shakeCompleteDuration) { [weak self] in
            self?.hide()
        }
    }

    // MARK: - Private Methods
    
    /// Start monitoring for Escape key globally.
    /// Needed because nonactivatingPanel doesn't become key window and won't receive key events.
    private func startEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                DispatchQueue.main.async {
                    self?.onEscapePressed?()
                }
            }
        }
    }
    
    /// Stop monitoring for Escape key.
    private func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private func configurePanel() {
        // Window level - float above normal windows
        level = .floating

        // Transparent background for custom HUD styling
        backgroundColor = .clear
        isOpaque = false

        // Collection behavior
        collectionBehavior = [
            .canJoinAllSpaces,      // Appear on all Spaces
            .fullScreenAuxiliary,   // Work with fullscreen apps
            .stationary             // Don't move with space switches
        ]

        // Don't hide when app loses focus
        hidesOnDeactivate = false

        // No title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Disable window shadow (SwiftUI view has its own shadow)
        hasShadow = false

        // Don't ignore mouse events anymore - we need to receive key events
        ignoresMouseEvents = false
    }

    private func setupContentView() {
        contentView = hostingView

        // Size to fit the SwiftUI content
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    /// Positions the panel at fixed bottom-center of the main screen.
    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - Self.panelWidth / 2
        let y = screenFrame.minY + Self.bottomMargin

        setFrameOrigin(CGPoint(x: x, y: y))
    }
}
