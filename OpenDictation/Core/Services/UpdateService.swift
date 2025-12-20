import Foundation
import Sparkle

/// Minimal Sparkle updater wrapper following the pattern used by top macOS apps
/// (Whisky, QuickRecorder, HuggingFace chat-macOS, etc.)
///
/// Usage:
/// - UpdateService.shared.updater for SPUUpdater access
/// - UpdateService.shared.checkForUpdates() for manual check
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    
    private let controller: SPUStandardUpdaterController
    private let delegate = UpdateServiceDelegate()
    
    /// The underlying SPUUpdater for bindings and state observation
    var updater: SPUUpdater { controller.updater }
    
    /// Published property that tracks whether updates can be checked
    @Published var canCheckForUpdates = false
    
    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        
        // Disable automatic update checks in debug builds (IINA+ pattern)
        // Manual "Check for Updates" still works from the menu
        #if DEBUG
        controller.updater.automaticallyChecksForUpdates = false
        #endif
        
        // Observe canCheckForUpdates from the updater
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    /// Manually check for updates (triggered by menu item or button)
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

// MARK: - Update Delegate

/// Separate delegate class to handle Sparkle callbacks.
/// This avoids Swift init order issues (can't pass self to constructor before init).
private final class UpdateServiceDelegate: NSObject, SPUUpdaterDelegate {
    
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // Set flag so post-update launch can detect this was an auto-update relaunch
        // Using synchronize() to ensure it's written before the process terminates
        UserDefaults.standard.set(true, forKey: kPostUpdateRelaunchKey)
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Post-Update Detection

/// File-level constant to avoid Swift concurrency issues with accessing MainActor-isolated properties
private let kPostUpdateRelaunchKey = "OpenDictation_PostUpdateRelaunch"

extension UpdateService {
    /// Checks and clears the post-update relaunch flag
    static func consumePostUpdateFlag() -> Bool {
        let value = UserDefaults.standard.bool(forKey: kPostUpdateRelaunchKey)
        if value {
            UserDefaults.standard.removeObject(forKey: kPostUpdateRelaunchKey)
        }
        return value
    }
}
