import AppKit
import ApplicationServices

/// Detects whether the currently focused UI element is a text field.
///
/// Uses macOS Accessibility APIs to check element roles and capabilities.
/// Fails gracefully to `false` if detection fails (e.g., permissions denied).
final class TextFieldDetector {
    
    // MARK: - Constants
    
    /// AXRole values that indicate a text input element.
    private static let textFieldRoles: Set<String> = [
        kAXTextFieldRole as String,      // "AXTextField"
        kAXTextAreaRole as String,       // "AXTextArea"
        "AXSearchField",
        kAXComboBoxRole as String,       // "AXComboBox"
        "AXSecureTextField"
    ]
    
    /// AXSubrole values that indicate text input capability.
    private static let textInputSubroles: Set<String> = [
        "AXSearchField",
        kAXSecureTextFieldSubrole as String,  // "AXSecureTextField"
        "AXTextInput"
    ]
    
    /// AXActions that indicate text editing capability.
    private static let textEditActions: Set<String> = [
        "AXInsertText",
        "AXDelete"
    ]
    
    // MARK: - Public Methods
    
    /// Checks if the currently focused element is a text field that can receive pasted text.
    ///
    /// Detection order:
    /// 1. Check AXRole (most reliable)
    /// 2. Check AXSubrole (for edge cases)
    /// 3. Check AXEditable attribute
    /// 4. Check AXActions for text editing capabilities
    ///
    /// - Returns: `true` if focused element appears to be a text field, `false` otherwise.
    ///            Returns `false` on any error (graceful fallback).
    func isInTextField() -> Bool {
        // Get the focused application
        guard let focusedApp = NSWorkspace.shared.frontmostApplication,
              let pid = focusedApp.processIdentifier as pid_t? else {
            return false
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }
        
        // Safe cast - we've verified the type above
        let axElement = element as! AXUIElement
        
        // Check role first (most reliable)
        if checkRole(of: axElement) {
            return true
        }
        
        // Check subrole for edge cases
        if checkSubrole(of: axElement) {
            return true
        }
        
        // Check if element is editable
        if checkEditable(of: axElement) {
            return true
        }
        
        // Check if element supports text editing actions
        if checkActions(of: axElement) {
            return true
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    /// Checks if the element's AXRole indicates a text field.
    private func checkRole(of element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        
        guard result == .success, let role = roleValue as? String else {
            return false
        }
        
        return Self.textFieldRoles.contains(role)
    }
    
    /// Checks if the element's AXSubrole indicates text input.
    private func checkSubrole(of element: AXUIElement) -> Bool {
        var subroleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        
        guard result == .success, let subrole = subroleValue as? String else {
            return false
        }
        
        return Self.textInputSubroles.contains(subrole)
    }
    
    /// Checks if the element has AXEditable set to true.
    private func checkEditable(of element: AXUIElement) -> Bool {
        var editableValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableValue)
        
        guard result == .success else {
            return false
        }
        
        // AXEditable can be a boolean
        if let editable = editableValue as? Bool {
            return editable
        }
        
        // Some apps return it as CFBoolean
        if let editable = editableValue as? NSNumber {
            return editable.boolValue
        }
        
        return false
    }
    
    /// Checks if the element supports text editing actions.
    private func checkActions(of element: AXUIElement) -> Bool {
        var actionNames: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNames)
        
        guard result == .success, let names = actionNames as? [String] else {
            return false
        }
        
        // Check if any text editing action is supported
        return !Self.textEditActions.isDisjoint(with: names)
    }
}
