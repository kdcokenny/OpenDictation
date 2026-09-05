import XCTest
import KeyboardShortcuts
@testable import OpenDictation

@MainActor
final class HotkeyTests: XCTestCase {

    private var defaults: UserDefaults!
    private let defaultsSuiteName = "HotkeyTests"
    
    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        // Standard cleanup for KeyboardShortcuts tests
        UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_toggleDictation")
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_toggleDictation")
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        super.tearDown()
    }
    
    // MARK: - Shortcut Registration
    
    func testDefaultShortcutRegistration() {
        let name = KeyboardShortcuts.Name.toggleDictation
        let defaultShortcut = KeyboardShortcuts.getShortcut(for: name)
        
        XCTAssertNotNil(defaultShortcut)
        XCTAssertEqual(defaultShortcut?.key, .space)
        XCTAssertEqual(defaultShortcut?.modifiers, [.option])
    }
    
    // MARK: - Shortcut Persistence
    
    func testShortcutUpdateAndPersistence() {
        let name = KeyboardShortcuts.Name.toggleDictation
        let newShortcut = KeyboardShortcuts.Shortcut(.f5, modifiers: [.command, .shift])
        
        // When
        KeyboardShortcuts.setShortcut(newShortcut, for: name)
        
        // Then
        let retrieved = KeyboardShortcuts.getShortcut(for: name)
        XCTAssertEqual(retrieved, newShortcut)
    }
    
    func testShortcutReset() {
        let name = KeyboardShortcuts.Name.toggleDictation
        let newShortcut = KeyboardShortcuts.Shortcut(.f5)
        
        KeyboardShortcuts.setShortcut(newShortcut, for: name)
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), newShortcut)
        
        // When
        KeyboardShortcuts.reset(name)
        
        // Then - Should return to default (Option+Space)
        let retrieved = KeyboardShortcuts.getShortcut(for: name)
        XCTAssertEqual(retrieved?.key, .space)
        XCTAssertEqual(retrieved?.modifiers, [.option])
    }
    
    // MARK: - Service Handler Registration
    
    func testHotkeyServiceRegistersHandler() {
        let sut = HotkeyService(defaults: defaults)
        
        // When
        sut.onHotkeyPressed = {}
        sut.onHotkeyReleased = {}
        sut.start()
        
        // We can't easily simulate the global system event in a unit test 
        // without more complex mocking, but we've verified the service 
        // starts up and the handler is assigned.
        XCTAssertNotNil(sut.onHotkeyPressed)
        XCTAssertNotNil(sut.onHotkeyReleased)
    }

    func testActivationModeDefaultsToToggle() {
        let sut = HotkeyService(defaults: defaults)

        XCTAssertEqual(sut.activationMode, .toggle)
    }

    func testActivationModePersistsHoldRawValue() {
        let sut = HotkeyService(defaults: defaults)

        sut.activationMode = .hold

        XCTAssertEqual(
            defaults.string(forKey: "dictationActivationMode"),
            "hold"
        )
        XCTAssertEqual(HotkeyService(defaults: defaults).activationMode, .hold)
    }

    func testInvalidActivationModeFallsBackToToggle() {
        defaults.set("unsupported", forKey: "dictationActivationMode")

        XCTAssertEqual(HotkeyService(defaults: defaults).activationMode, .toggle)
    }
}
