import AppKit
import AVFoundation
import Combine
import os.log

/// Manages system permissions required by Open Dictation.
///
/// Handles checking and requesting Accessibility and Microphone permissions.
/// Uses DistributedNotificationCenter to detect permission changes in System Settings.
///
/// Key design principles (following Loop, iTerm2, VoiceInk, CodeLooper patterns):
/// - Check permissions silently (no prompt) on launch
/// - Prompt only once per app version for accessibility
/// - Defer microphone prompt until user actually tries to record
/// - Listen for permission changes via notification instead of polling
/// - Show alert with choice for denied permissions (don't auto-open Settings)
/// - Reset stale TCC entries before requesting (Loop pattern for ad-hoc signed apps)
@MainActor
final class PermissionsManager: ObservableObject {
    
    // MARK: - Constants
    
    private enum Keys {
        static let accessibilityPromptedVersion = "PermissionsManager_AccessibilityPromptedVersion"
        static let lastLaunchedBuildNumber = "PermissionsManager_LastLaunchedBuildNumber"
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var isAccessibilityGranted: Bool = false
    @Published private(set) var isMicrophoneGranted: Bool = false
    
    /// Publishes when accessibility permissions have been updated.
    let accessibilityDidUpdate = PassthroughSubject<Void, Never>()
    
    // MARK: - Private Properties
    
    private let logger = Logger.app(category: "PermissionsManager")
    private var accessibilityObserver: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        refreshPermissionStatus()
    }
    
    deinit {
        accessibilityObserver?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Refreshes the current status of all permissions (no prompts).
    func refreshPermissionStatus() {
        isAccessibilityGranted = AXIsProcessTrusted()
        isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Starts observing permission changes via DistributedNotificationCenter.
    ///
    /// This listens for the `com.apple.accessibility.api` notification which fires
    /// when ANY app's accessibility permission changes in System Settings.
    /// Much more efficient than polling.
    func startObserving() {
        guard accessibilityObserver == nil else { return }
        
        accessibilityObserver = Task { [weak self] in
            let notificationName = Notification.Name("com.apple.accessibility.api")
            let notifications = DistributedNotificationCenter.default().notifications(named: notificationName)
            
            for await _ in notifications {
                // Notification fires before state updates - add small delay
                // (Pattern from Loop, Squirrel, MonitorControl)
                try? await Task.sleep(for: .milliseconds(250))
                
                await MainActor.run {
                    self?.refreshPermissionStatus()
                    self?.accessibilityDidUpdate.send()
                }
            }
        }
    }
    
    // MARK: - Launch-Time Permission Check
    
    /// Checks accessibility permission on app launch with custom UI.
    ///
    /// This method follows the pattern from Touch Bar Simulator by Sindre Sorhus:
    /// - Returns immediately if permission already granted
    /// - Resets stale TCC entries (Loop pattern for ad-hoc signed apps)
    /// - Opens System Settings to Accessibility pane
    /// - Shows custom alert explaining what's needed
    /// - Offers "Continue" or "Quit" buttons
    /// - Relaunches app after user grants permission
    ///
    /// This prevents the escape key bug by ensuring accessibility is granted
    /// before any event taps are created.
    func checkAccessibilityOnLaunch() {
        // We intentionally don't use the system prompt as our dialog explains it better.
        // Use the raw string value to avoid Swift 6 concurrency issues with the global constant
        // kAXTrustedCheckOptionPrompt's value is "AXTrustedCheckOptionPrompt"
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            // Already granted - update status and continue
            isAccessibilityGranted = true
            return
        }
        
        // Reset any stale TCC entries before requesting permission.
        // This is critical for ad-hoc signed apps: after an update, the app's code signature
        // changes, but the old TCC entry remains. The user sees "Open Dictation" checked in
        // System Settings, but AXIsProcessTrusted() returns false because the signature
        // doesn't match. Resetting clears this stale state.
        // Pattern from Loop (github.com/MrKai77/Loop).
        logger.info("Accessibility not granted - resetting TCC to clear any stale entries")
        resetAccessibility()
        
        // Open System Settings to Accessibility pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        
        // Force our app to front so alert appears on top (Clipy pattern)
        NSApp.activate(ignoringOtherApps: true)
        
        // Show custom alert explaining what's needed
        let alert = NSAlert()
        alert.messageText = "Open Dictation needs accessibility access."
        alert.informativeText = """
        Open Dictation needs accessibility to paste transcribed text directly into other apps.
        
        In the System Settings window that just opened, find "Open Dictation" in the list and check its checkbox. Then click the "Continue" button here.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Quit")
        
        guard alert.runModal() == .alertFirstButtonReturn else {
            // User clicked "Quit"
            NSApp.terminate(nil)
            return
        }
        
        // Verify user actually granted permission before relaunching
        // This prevents infinite loop if user clicks "Continue" without granting permission
        if !AXIsProcessTrustedWithOptions(options) {
            // Still not granted - show error and quit
            let errorAlert = NSAlert()
            errorAlert.messageText = "Permission not granted"
            errorAlert.informativeText = "Open Dictation cannot continue without accessibility permission. Please enable it in System Settings and relaunch the app."
            errorAlert.alertStyle = .critical
            errorAlert.addButton(withTitle: "Quit")
            errorAlert.runModal()
            NSApp.terminate(nil)
            return
        }
        
        // Permission granted - relaunch to ensure clean state
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    NSApp.presentError(error)
                    return
                }
                
                NSApp.terminate(nil)
            }
        }
    }
    
    // MARK: - Post-Update Handling
    
    /// Detects if this launch is after an app update that changed the binary.
    /// Uses version comparison as primary signal (reliable) with delegate flag as optimization.
    func isPostUpdateLaunch() -> Bool {
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let lastBuild = UserDefaults.standard.string(forKey: Keys.lastLaunchedBuildNumber)
        
        // Always update for next launch
        UserDefaults.standard.set(currentBuild, forKey: Keys.lastLaunchedBuildNumber)
        
        // Post-update if: (1) build changed, OR (2) Sparkle delegate set flag
        let buildChanged = (lastBuild != nil) && (lastBuild != currentBuild)
        let delegateFlag = UpdateService.consumePostUpdateFlag()
        
        if buildChanged || delegateFlag {
            logger.info("Detected post-update launch (buildChanged: \(buildChanged), delegateFlag: \(delegateFlag))")
            return true
        }
        
        return false
    }
    
    /// Handles accessibility check specifically after an auto-update.
    /// Terminates app so user can manually relaunch for proper TCC registration.
    func handlePostUpdateAccessibilityCheck() {
        // Already granted? Continue normally (user may have manually fixed or relaunch worked)
        if AXIsProcessTrusted() {
            logger.info("Accessibility already granted on post-update launch")
            isAccessibilityGranted = true
            return
        }
        
        logger.info("Post-update launch detected - accessibility not granted")
        
        // Force app to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Reset stale TCC entries
        let resetSucceeded = resetAccessibilityAndReturnStatus()
        
        if resetSucceeded {
            showPostUpdateQuitDialog()
        } else {
            showManualRemovalDialog()
        }
        
        NSApp.terminate(nil)
    }
    
    /// Shows dialog when tccutil reset succeeded.
    private func showPostUpdateQuitDialog() {
        let alert = NSAlert()
        alert.messageText = "One More Step After Update"
        alert.informativeText = """
        Open Dictation was just updated. macOS security requires you to:
        
        1. Click "Quit" below
        2. Reopen Open Dictation from the Dock or Applications folder
        3. Enable accessibility permission when prompted
        
        This is a one-time step after updates.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Open Applications Folder")
        
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "/Applications")
        }
    }
    
    /// Shows dialog when tccutil reset FAILED - user must manually remove.
    private func showManualRemovalDialog() {
        let alert = NSAlert()
        alert.messageText = "Manual Step Required"
        alert.informativeText = """
        Open Dictation was just updated, but automatic permission reset failed.
        
        Please follow these steps:
        
        1. Click "Open System Settings" below
        2. Find "Open Dictation" in the list
        3. Click the minus (-) button to REMOVE it
        4. Close this app and reopen it
        5. Re-add Open Dictation when prompted
        
        Toggling the checkbox off/on will NOT work—you must fully remove it.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Resets accessibility and returns whether it succeeded.
    private nonisolated func resetAccessibilityAndReturnStatus() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            
            let log = OSLog.app(category: "PermissionsManager")
            if process.terminationStatus == 0 {
                os_log("Reset accessibility permissions for %{public}@", log: log, type: .info, bundleID)
                return true
            } else {
                os_log("tccutil reset failed with status %d", log: log, type: .error, process.terminationStatus)
                return false
            }
        } catch {
            let log = OSLog.app(category: "PermissionsManager")
            os_log("Failed to run tccutil: %{public}@", log: log, type: .error, error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Accessibility Permission
    
    /// Requests Accessibility permission if not already prompted this app version.
    ///
    /// Pattern from iTerm2: Only show the system prompt once per app version.
    /// If already prompted this version, opens System Settings directly instead.
    /// Also resets stale TCC entries (Loop pattern for ad-hoc signed apps).
    ///
    /// - Returns: `true` if permission is granted, `false` if denied or pending.
    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        // Already granted - no action needed
        if isAccessibilityGranted {
            return true
        }
        
        // Reset any stale TCC entries before requesting permission.
        // Pattern from Loop - ensures the permission request will work even after app updates.
        logger.info("Accessibility not granted - resetting TCC before request")
        resetAccessibility()
        
        // Check if we've already prompted this version
        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let promptedVersion = UserDefaults.standard.string(forKey: Keys.accessibilityPromptedVersion)
        
        if currentVersion == promptedVersion {
            // Already prompted this version - open System Settings directly (no spam)
            openAccessibilitySettings()
            return false
        }
        
        // First prompt for this version - show system dialog
        if let currentVersion = currentVersion {
            UserDefaults.standard.set(currentVersion, forKey: Keys.accessibilityPromptedVersion)
        }
        
        // Use the raw string value to avoid Swift 6 concurrency issues with the global constant
        // kAXTrustedCheckOptionPrompt's value is "AXTrustedCheckOptionPrompt"
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        
        // Update status after prompt
        isAccessibilityGranted = result
        return result
    }
    
    /// Opens System Settings > Privacy & Security > Accessibility directly.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Microphone Permission
    
    /// Requests Microphone permission asynchronously.
    ///
    /// Call this when the user actually tries to record, not on app launch.
    /// This follows Apple's guidance to request permissions in context.
    ///
    /// - Parameter completion: Called with `true` if granted, `false` if denied.
    func requestMicrophoneIfNeeded(completion: @escaping @MainActor (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            isMicrophoneGranted = true
            completion(true)
            
        case .notDetermined:
            // First time - show system prompt
            // Use DispatchQueue.main.async (traditional GCD pattern) instead of Task { @MainActor in }
            // for more reliable callback dispatch after permission grant
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicrophoneGranted = granted
                    completion(granted)
                }
            }
            
        case .denied, .restricted:
            isMicrophoneGranted = false
            // Show alert with choice instead of auto-opening Settings (CodeLooper pattern)
            showMicrophonePermissionDeniedAlert()
            completion(false)
            
        @unknown default:
            isMicrophoneGranted = false
            completion(false)
        }
    }
    
    // MARK: - Private Methods
    
    /// Shows an alert when microphone permission is denied, with option to open Settings.
    /// Pattern from CodeLooper - gives user choice instead of auto-opening Settings every time.
    private func showMicrophonePermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText = "Open Dictation needs microphone access to transcribe your speech. Please enable it in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Resets accessibility permissions for this app's bundle ID.
    ///
    /// This is critical for ad-hoc signed apps (like Open Dictation distributed via GitHub).
    /// When the app is updated, the code signature changes, but macOS TCC database may still
    /// have the old entry. This creates a "stale" permission where:
    /// - System Settings shows the app as having permission (based on bundle ID)
    /// - But `AXIsProcessTrusted()` returns false (code signature doesn't match)
    ///
    /// Running `tccutil reset Accessibility <bundle-id>` clears all entries for this bundle ID,
    /// allowing the user to grant fresh permission that matches the current code signature.
    ///
    /// Pattern from Loop (github.com/MrKai77/Loop) - the leading open-source window manager.
    private nonisolated func resetAccessibility() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        
        let tccutilPath = "/usr/bin/tccutil"
        let arguments = ["reset", "Accessibility", bundleID]
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tccutilPath)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            
            // Log result (can't use logger from nonisolated context, use OSLog.app() directly)
            let log = OSLog.app(category: "PermissionsManager")
            if process.terminationStatus == 0 {
                os_log("Reset accessibility permissions for %{public}@", log: log, type: .info, bundleID)
            } else {
                os_log("tccutil reset failed with status %d", log: log, type: .error, process.terminationStatus)
            }
        } catch {
            let log = OSLog.app(category: "PermissionsManager")
            os_log("Failed to run tccutil: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }
}
