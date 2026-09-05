import XCTest
import AppKit
@testable import OpenDictation

@MainActor
final class TextInsertionTests: XCTestCase {
    
    private var sut: TextInsertionService!
    private let pasteboard = NSPasteboard.general
    private var pasteboardSnapshot: [[NSPasteboard.PasteboardType: Data]] = []
    
    override func setUp() async throws {
        try await super.setUp()
        pasteboardSnapshot = savePasteboardContents(pasteboard)
        sut = TextInsertionService(
            accessibilityChecker: MockAccessibilityChecker(isGranted: true),
            pasteSimulator: { true }
        )
        pasteboard.clearContents()
    }
    
    override func tearDown() async throws {
        restorePasteboardContents(pasteboardSnapshot, to: pasteboard)
        pasteboardSnapshot = []
        sut = nil
        try await super.tearDown()
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

    func testAutomaticallyRestoresClipboardWithoutUIDismissal() async throws {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("Original Content", forType: .string)
        let automaticRestoreSut = TextInsertionService(
            accessibilityChecker: MockAccessibilityChecker(isGranted: true),
            pasteSimulator: { true },
            clipboardRestoreDelay: .milliseconds(10)
        )

        XCTAssertEqual(automaticRestoreSut.insertText("Dictated Text"), .inserted)
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictated Text")

        let didRestore = try await waitForPasteboardString(
            "Original Content",
            timeout: 1
        )

        XCTAssertTrue(didRestore, "Clipboard restoration did not finish before the timeout")
    }
    
    // MARK: - Fallback Logic
    
    func testFallbackToClipboardOnlyWhenNoAccessibility() {
        // Given
        let fallbackSut = TextInsertionService(accessibilityChecker: MockAccessibilityChecker(isGranted: false))
        let newText = "Fallback Text"
        
        // When
        let result = fallbackSut.insertText(newText)
        
        // Then
        XCTAssertEqual(result, .copiedOnly, "Should return copiedOnly when accessibility is missing")
        XCTAssertEqual(pasteboard.string(forType: .string), newText, "Should still set clipboard as fallback")
    }

    func testReportsFailureWhenPasteSimulationFails() {
        // Given
        let failingSut = TextInsertionService(
            accessibilityChecker: MockAccessibilityChecker(isGranted: true),
            pasteSimulator: { false }
        )
        pasteboard.clearContents()
        pasteboard.setString("Original", forType: .string)

        // When
        let result = failingSut.insertText("New Text")

        // Then
        XCTAssertEqual(result, .failed("Failed to simulate paste."))
        XCTAssertEqual(pasteboard.string(forType: .string), "Original")
    }
    
    // MARK: - Verification Logic
    
    func testDoesNotRestoreWhenClipboardChanges() {
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

    func testDoesNotRestoreAfterUserCopiesIdenticalText() {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("Original Content", forType: .string)

        XCTAssertEqual(sut.insertText("Dictated Text"), .inserted)

        pasteboard.clearContents()
        pasteboard.setString("Dictated Text", forType: .string)
        sut.restoreClipboard()

        XCTAssertEqual(pasteboard.string(forType: .string), "Dictated Text")
    }

    private func waitForPasteboardString(
        _ expected: String,
        timeout: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if pasteboard.string(forType: .string) == expected {
                return true
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        return pasteboard.string(forType: .string) == expected
    }

    private func savePasteboardContents(
        _ pasteboard: NSPasteboard
    ) -> [[NSPasteboard.PasteboardType: Data]] {
        var items: [[NSPasteboard.PasteboardType: Data]] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            if !itemData.isEmpty {
                items.append(itemData)
            }
        }

        return items
    }

    private func restorePasteboardContents(
        _ savedItems: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()

        guard !savedItems.isEmpty else { return }

        let pasteboardItems = savedItems.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        XCTAssertTrue(
            pasteboard.writeObjects(pasteboardItems),
            "Failed to restore pasteboard contents"
        )
    }
}
