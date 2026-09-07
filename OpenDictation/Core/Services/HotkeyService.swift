import Foundation
import KeyboardShortcuts
import os.log

enum DictationActivationMode: String, CaseIterable, Identifiable {
    case toggle
    case hold

    static let storageKey = "dictationActivationMode"

    var id: String { rawValue }
}

// MARK: - Shortcut Name Registration

extension KeyboardShortcuts.Name {
    /// Global hotkey for toggling dictation (Option+Space by default)
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.option]))
}

// MARK: - HotkeyService

/// Manages global keyboard shortcuts using KeyboardShortcuts library.
@MainActor
final class HotkeyService {
    
    private let logger = Logger.app(category: "HotkeyService")
    
    /// Called when the hotkey is pressed.
    var onHotkeyPressed: (() -> Void)?

    /// Called when the hotkey is released.
    var onHotkeyReleased: (() -> Void)?

    private let defaults: UserDefaults

    var activationMode: DictationActivationMode {
        get {
            let rawValue = defaults.string(forKey: DictationActivationMode.storageKey)
            return rawValue.flatMap(DictationActivationMode.init(rawValue:)) ?? .toggle
        }
        set {
            defaults.set(newValue.rawValue, forKey: DictationActivationMode.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// Start listening for the global hotkey.
    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.onHotkeyPressed?()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            self?.onHotkeyReleased?()
        }
        logger.debug("Listening for hotkey")
    }
}
