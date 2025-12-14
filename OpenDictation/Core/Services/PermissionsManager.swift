import AppKit
import AVFoundation
import Combine

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
@MainActor
final class PermissionsManager: ObservableObject {
    
    // MARK: - Constants
    
    private enum Keys {
        static let accessibilityPromptedVersion = "PermissionsManager_AccessibilityPromptedVersion"
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var isAccessibilityGranted: Bool = false
    @Published private(set) var isMicrophoneGranted: Bool = false
    
    /// Publishes when accessibility permissions have been updated.
    let accessibilityDidUpdate = PassthroughSubject<Void, Never>()
    
    // MARK: - Private Properties
    
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
    
    // MARK: - Accessibility Permission
    
    /// Requests Accessibility permission if not already prompted this app version.
    ///
    /// Pattern from iTerm2: Only show the system prompt once per app version.
    /// If already prompted this version, opens System Settings directly instead.
    ///
    /// - Returns: `true` if permission is granted, `false` if denied or pending.
    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        // Already granted - no action needed
        if isAccessibilityGranted {
            return true
        }
        
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
}
