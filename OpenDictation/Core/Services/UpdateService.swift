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
    
    /// The underlying SPUUpdater for bindings and state observation
    var updater: SPUUpdater { controller.updater }
    
    /// Published property that tracks whether updates can be checked
    @Published var canCheckForUpdates = false
    
    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
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
