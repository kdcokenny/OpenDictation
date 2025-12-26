import ApplicationServices

/// Protocol for checking accessibility permissions.
/// Enables dependency injection for testing.
protocol AccessibilityChecker {
    var isAccessibilityGranted: Bool { get }
}

/// Default implementation using system AXIsProcessTrusted().
struct SystemAccessibilityChecker: AccessibilityChecker {
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
