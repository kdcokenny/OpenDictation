import XCTest
import AppKit
@testable import OpenDictation

@MainActor
final class TextInsertionTests: XCTestCase {
    
    private var sut: TextInsertionService!
    private let pasteboard = NSPasteboard.general
    
    override func setUp() {
        super.setUp()
        sut = TextInsertionService(accessibilityChecker: MockAccessibilityChecker(isGranted: true))
        pasteboard.clearContents()
    }
    
    override func tearDown() {
        pasteboard.clearContents()
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Clipboard Preservation
    
    func testPreservesOriginalClipboardContent() {
        // Given
        let originalText = "Original Content"
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(originalText, forType: .string)
        
        let newText = "New Snippet"
        
        // When
        // With MockAccessibilityChecker(isGranted: true), the service simulates Cmd+V
        // and preserves the original clipboard via pendingRestore for later restoration.
        _ = sut.insertText(newText)
        
        // Verify it was set (even in fallback mode it sets the clipboard)
        XCTAssertEqual(pasteboard.string(forType: .string), newText)
        
        // Then restore
        sut.restoreClipboard()
        
        // Verify original content is back
        XCTAssertEqual(pasteboard.string(forType: .string), originalText)
    }
    
    func testPreservesComplexClipboardContent() {
        // Given
        let originalText = "Plain Text"
        let rtfData = "{\\rtf1\\ansicontent}".data(using: .utf8)!
        
        pasteboard.declareTypes([.string, .rtf], owner: nil)
        pasteboard.setString(originalText, forType: .string)
        pasteboard.setData(rtfData, forType: .rtf)
        
        let newText = "Dictated Text"
        
        // When
        _ = sut.insertText(newText)
        sut.restoreClipboard()
        
        // Then
        XCTAssertEqual(pasteboard.string(forType: .string), originalText)
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtfData)
    }
    
    // MARK: - Fallback Logic
    
    func testFallbackToClipboardOnlyWhenNoAccessibility() {
        // Given
        let fallbackSut = TextInsertionService(accessibilityChecker: MockAccessibilityChecker(isGranted: false))
        let newText = "Fallback Text"
        
        // When
        let result = fallbackSut.insertText(newText)
        
        // Then
        XCTAssertFalse(result, "Should return false when accessibility is missing")
        XCTAssertEqual(pasteboard.string(forType: .string), newText, "Should still set clipboard as fallback")
    }
    
    // MARK: - Verification Logic
    
    func testRestoresOnVerificationFailure() {
        // This is hard to test without mocking the pasteboard, 
        // but we can verify the logic of restoreClipboard() 
        // doesn't restore if the clipboard was changed by user.
        
        let originalText = "Keep Me"
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(originalText, forType: .string)
        
        _ = sut.insertText("New Text")
        
        // User manually copies something else
        pasteboard.clearContents()
        pasteboard.setString("User Copied", forType: .string)
        
        // When
        sut.restoreClipboard()
        
        // Then - Should NOT restore original text because clipboard was modified
        XCTAssertEqual(pasteboard.string(forType: .string), "User Copied")
    }
}
