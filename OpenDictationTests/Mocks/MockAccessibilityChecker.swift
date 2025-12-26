@testable import OpenDictation

struct MockAccessibilityChecker: AccessibilityChecker {
    var isAccessibilityGranted: Bool
    
    init(isGranted: Bool = true) {
        self.isAccessibilityGranted = isGranted
    }
}
