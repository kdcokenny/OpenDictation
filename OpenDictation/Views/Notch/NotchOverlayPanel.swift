import AppKit
import SwiftUI
import CoreGraphics
import os.log

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
    
    private let logger = Logger.app(category: "NotchOverlayPanel")
    private var window: NotchWindow?
    private var hostingView: NSHostingView<NotchDictationView>?
    private let viewModel = NotchViewModel()
    private let screen: NSScreen
    
    /// Callback when dismiss animation completes.
    var onDismissCompleted: (() -> Void)?
    
    /// Flag to prevent multiple dismiss calls.
    private var isDismissing = false
    
    /// Whether the panel window is currently visible.
    var isVisible: Bool {
        return window?.isVisible == true
    }
    
    /// Whether the panel is in a healthy state (window exists and is valid).
    /// Used for defensive recovery when the window may have become stale.
    var isHealthy: Bool {
        guard let window = window else {
            logger.debug("Health check: window is nil")
            return false
        }
        
        guard window.contentView != nil else {
            logger.warning("Health check: contentView is nil")
            return false
        }
        
        guard window.level == .screenSaver else {
            logger.warning("Health check: window level demoted from .screenSaver(1000) to \(window.level.rawValue)")
            return false
        }
        
        // Check window is positioned on a valid screen
        let windowOnScreen = NSScreen.screens.contains { screen in
            screen.frame.intersects(window.frame)
        }
        guard windowOnScreen else {
            logger.warning("Health check: window frame not on any screen")
            return false
        }
        
        return true
    }
    
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
    /// - Parameter isRetry: Whether this is a retry attempt after a recovery action.
    func show(isRetry: Bool = false) {
        isDismissing = false
        viewModel.setVisualState(.recording)
        
        // Create window if needed
        if window == nil {
            createWindow()
        }
        
        guard let window = window else { return }
        
        // 1. Re-apply window config
        // This prevents macOS from silently modifying window properties over time.
        window.level = .screenSaver
        let defaultBehavior: NSWindow.CollectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        // 2. Handling for "Window stuck on wrong space"
        if !window.isOnActiveSpace {
            logger.warning("Window not on active space, attempting force move")
            window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            window.orderFrontRegardless()
            window.collectionBehavior = defaultBehavior
        } else {
            window.collectionBehavior = defaultBehavior
            window.orderFrontRegardless()
        }
        
        // 3. Self-healing Recovery
        // If the window is still not on the active space despite our efforts,
        // it means the window instance is corrupted in the Window Server (common after sleep/wake).
        // We destroy and recreate the instance exactly once.
        if !window.isOnActiveSpace && !isRetry {
            logger.info("Window space corruption detected. Triggering self-healing recovery.")
            
            let savedCallback = onDismissCompleted
            destroy()
            onDismissCompleted = savedCallback
            
            show(isRetry: true)
            return
        }
        
        // Log failure if still not visible after retry
        if !window.isVisible || !window.isOnActiveSpace {
             logger.error("Final visibility check failed - isVisible: \(window.isVisible), isOnSpace: \(window.isOnActiveSpace)")
        }
        
        // Apply 100ms render delay before expanding
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
    
    /// Destroys the panel synchronously for clean shutdown during screen changes.
    /// This ensures no async callbacks fire after the panel reference is cleared.
    func destroy() {
        // Clear callbacks to prevent dangling references
        onDismissCompleted = nil
        
        // Immediate window close (no animation)
        window?.orderOut(nil)
        window?.close()
        window = nil
        hostingView = nil
        
        isDismissing = false
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
}
