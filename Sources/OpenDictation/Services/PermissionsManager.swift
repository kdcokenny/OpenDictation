import AppKit
import AVFoundation
import Combine

/// Manages system permissions required by Open Dictate.
///
/// Handles checking and requesting Accessibility and Microphone permissions,
/// with polling support to detect when users grant permissions via System Settings.
final class PermissionsManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isAccessibilityGranted: Bool = false
    @Published private(set) var isMicrophoneGranted: Bool = false
    
    /// Returns true only when both Accessibility and Microphone permissions are granted.
    var allPermissionsGranted: Bool {
        isAccessibilityGranted && isMicrophoneGranted
    }
    
    // MARK: - Private Properties
    
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    init() {
        refreshPermissionStatus()
    }
    
    deinit {
        stopPolling()
    }
    
    // MARK: - Public Methods
    
    /// Refreshes the current status of all permissions.
    func refreshPermissionStatus() {
        isAccessibilityGranted = checkAccessibilityPermission()
        isMicrophoneGranted = checkMicrophonePermission()
    }
    
    /// Requests Accessibility permission by prompting the system dialog.
    ///
    /// This opens System Settings > Privacy & Security > Accessibility if the user
    /// hasn't granted permission yet.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Update status after request
        isAccessibilityGranted = checkAccessibilityPermission()
    }
    
    /// Requests Microphone permission asynchronously.
    ///
    /// Call this during app setup so permission is determined before the user tries to record.
    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        guard status == .notDetermined else {
            // Already determined - just refresh status
            isMicrophoneGranted = (status == .authorized)
            return
        }
        
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isMicrophoneGranted = granted
            }
        }
    }
    
    /// Starts polling for permission status changes.
    ///
    /// This is useful because users may grant permissions in System Settings
    /// outside of our app, and we need to detect when that happens.
    func startPolling() {
        guard pollingTimer == nil else { return }
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }
    
    /// Stops polling for permission status changes.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }
    
    private func checkMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }
}
