import AppKit

/// A borderless panel configured to overlay the notch area.
/// Uses production-proven pattern from DynamicNotchKit, KeyboardCowboy, and other overlay apps.
///
/// Configuration:
/// - `.screenSaver` level (1000) for guaranteed visibility over fullscreen apps
/// - Borderless with full-size content for custom drawing
/// - Works on all Spaces, doesn't appear in window cycling
/// - Does not steal focus from active application
/// - `becomesKeyOnlyIfNeeded = true` prevents system window demotion
final class NotchWindow: NSPanel {
    
    // MARK: - Constants
    
    /// Render delay to avoid glitches on first display.
    /// Discovered by NotchDrop as critical for correct rendering.
    static let renderDelay: TimeInterval = 0.1
    
    // MARK: - Initialization
    
    init(screen: NSScreen) {
        // Position window at top of screen, spanning full width
        let screenFrame = screen.frame
        let notchHeight = screen.safeAreaInsets.top
        
        // Window covers the notch area at top of screen
        let windowFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - notchHeight,
            width: screenFrame.width,
            height: notchHeight
        )
        
        super.init(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
    }
    
    // MARK: - NSWindow Overrides
    
    /// Never become key window - prevents focus stealing (Apple system UI pattern).
    override var canBecomeKey: Bool { false }
    
    /// Never become main window - prevents focus stealing (Apple system UI pattern).
    override var canBecomeMain: Bool { false }
    
    // MARK: - Private Configuration
    
    private func configureWindow() {
        // Floating panel behavior (Apple system UI pattern)
        isFloatingPanel = true
        
        // Prevent system from demoting window priority after system events.
        // Combined with canBecomeKey = false, this maintains passive behavior
        // while ensuring reliable visibility. Pattern from KeyboardCowboy.
        becomesKeyOnlyIfNeeded = true
        
        // Window level - .screenSaver (1000) for guaranteed visibility over fullscreen apps.
        // This is the Apple-blessed pattern used by DynamicNotchKit, KeyboardCowboy,
        // and other production overlay apps for reliable fullscreen compatibility.
        level = .screenSaver
        
        // Transparent background for custom content
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        
        // Collection behavior for system integration
        collectionBehavior = [
            .fullScreenAuxiliary,   // Work with fullscreen apps
            .stationary,            // Don't move with Space switches
            .canJoinAllSpaces,      // Appear on all Spaces
            .ignoresCycle           // Don't appear in Cmd+Tab
        ]
        
        // Don't hide when app loses focus
        hidesOnDeactivate = false
        
        // No title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }
}
