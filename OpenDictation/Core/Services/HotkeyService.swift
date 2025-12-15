import KeyboardShortcuts
import os.log

// MARK: - Shortcut Name Registration

extension KeyboardShortcuts.Name {
    /// Global hotkey for toggling dictation (Option+Space by default)
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.option]))
}

// MARK: - HotkeyService

/// Manages global keyboard shortcuts using KeyboardShortcuts library.
final class HotkeyService {
    
    private let logger = Logger.app(category: "HotkeyService")
    
    /// Called when the hotkey is pressed.
    var onHotkeyPressed: (() -> Void)?
    
    /// Start listening for the global hotkey.
    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.onHotkeyPressed?()
        }
        logger.debug("Listening for hotkey")
    }
}
