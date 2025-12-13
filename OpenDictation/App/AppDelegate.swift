import AppKit
import SwiftUI
import Combine
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    // MARK: - Logger
    
    private let logger = Logger(subsystem: "com.opendictation", category: "AppDelegate")
    
    // MARK: - Constants
    
    private enum Timing {
        /// Delay before playing start sound (after volume duck begins)
        static let volumeDuckRampDelay: TimeInterval = 0.15
        /// Delay before restoring volume (after feedback sound starts)
        static let volumeRestoreDelay: TimeInterval = 0.4
        /// Brief delay to allow UI to update before showing processing
        static let transcriptionStartedDelay: TimeInterval = 0.1
    }
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var permissionsManager: PermissionsManager?
    private var notchPanel: NotchOverlayPanel?
    private var textInsertionService: TextInsertionService?
    private var audioFeedbackService: AudioFeedbackService?
    private var hotkeyService: HotkeyService?
    private var recordingService: RecordingService?
    private var stateMachine: DictationStateMachine?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    /// Active transcription task (for cancellation support)
    private var transcriptionTask: Task<Void, Never>?
    
    // MARK: - NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if app should be moved to Applications (before other setup)
        ApplicationMover.checkAndOfferToMoveToApplications()
        
        setupStatusItem()
        setupServices()
        setupStateMachine()
        setupLocalTranscription()
        
        // Initialize updater (starts automatic update checks)
        _ = UpdateService.shared
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Restore volume if still ducked (safety net)
        audioFeedbackService?.restoreVolume()
        notchPanel?.hide()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem?.button else { return }
        // Use custom menu bar icon (template image for automatic light/dark mode adaptation)
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            icon.accessibilityDescription = "Open Dictation"
            button.image = icon
        } else {
            // Fallback to SF Symbol if custom icon not found
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Open Dictation")
        }
        
        let menu = NSMenu()
        
        // Debug submenu (only in DEBUG builds)
        #if DEBUG
        let debugMenu = NSMenu(title: "Debug")
        
        let testErrorItem = NSMenuItem(title: "Test: Error State", action: #selector(testErrorFlow), keyEquivalent: "")
        testErrorItem.target = self
        debugMenu.addItem(testErrorItem)
        
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        #endif
        
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Open Dictation",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func setupServices() {
        permissionsManager = PermissionsManager()
        textInsertionService = TextInsertionService()
        audioFeedbackService = AudioFeedbackService()
        hotkeyService = HotkeyService()
        recordingService = RecordingService.shared
        
        // Create notch panel only if device has hardware notch
        // Non-notch Macs get audio feedback only (no visual UI)
        if let notchScreen = NSScreen.screenWithNotch {
            notchPanel = NotchOverlayPanel(screen: notchScreen)
            logger.info("Notch detected - using notch-based dictation UI")
        } else {
            logger.info("No notch detected - audio feedback only (no visual UI)")
        }
        
        // Start listening for permission changes (via DistributedNotificationCenter)
        permissionsManager?.startObserving()
        
        // Log permission status on launch (no prompts - just checks)
        if let pm = permissionsManager {
            logger.debug("Accessibility granted: \(pm.isAccessibilityGranted)")
            logger.debug("Microphone granted: \(pm.isMicrophoneGranted)")
            
            // NOTE: Permissions are now requested lazily:
            // - Accessibility: prompted once per version when hotkey is first pressed
            // - Microphone: prompted when user first tries to record
        }
    }
    
    /// Sets up local transcription on first launch.
    /// Copies bundled model to Application Support and checks for auto-upgrade.
    private func setupLocalTranscription() {
        Task {
            // Copy bundled model if this is first launch
            await ModelManager.shared.setupBundledModelIfNeeded()
            
            // First launch setup - default to local mode (no keychain access needed)
            // Keychain is only accessed when user explicitly opens Settings or uses cloud mode
            let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            
            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                
                // Default to local mode unconditionally (works out of box, no API key check needed)
                TranscriptionCoordinator.shared.setMode(.local)
                self.logger.info("First launch: defaulting to local transcription mode")
            }
            
            // Validate current mode
            if let error = await TranscriptionCoordinator.shared.validateCurrentMode() {
                self.logger.warning("Transcription mode issue: \(error)")
            }
            
            // Check if auto-upgrade is needed (downloads better model if on Wi-Fi)
            await ModelManager.shared.checkAndUpgradeIfNeeded()
        }
    }
    
    private func setupStateMachine() {
        let sm = DictationStateMachine()
        stateMachine = sm
        
        // Wire up panel callbacks (only if notch panel exists)
        notchPanel?.onEscapePressed = { [weak sm] in
            sm?.send(.escapePressed)
        }
        
        notchPanel?.onDismissCompleted = { [weak sm] in
            sm?.send(.dismissCompleted)
        }
        
        // Wire up audio level for real-time waveform visualization
        recordingService?.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.notchPanel?.setAudioLevel(level)
            }
            .store(in: &cancellables)
        
        // Wire up state machine callbacks
        sm.onShowPanel = { [weak self] in
            // Duck other audio first, then play start sound
            // AudioDeviceDuck only affects OTHER audio, our sounds play at full volume
            self?.audioFeedbackService?.duckVolume()
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.volumeDuckRampDelay) {
                self?.audioFeedbackService?.playStartSound()
            }
            // Only show panel if notch exists (non-notch Macs get audio feedback only)
            self?.notchPanel?.show()
        }
        
        sm.onHidePanel = { [weak self, weak sm] in
            guard let self = self, let sm = sm else { return }
            
            // Only hide panel if it exists (non-notch Macs skip this)
            guard let panel = self.notchPanel else {
                // No panel - just trigger dismiss completed callback
                sm.send(.dismissCompleted)
                return
            }
            
            switch sm.state {
            case .success:
                panel.showSuccessAndDismiss()
            case .copiedToClipboard:
                panel.showClipboardAndDismiss()
            case .error(_):
                panel.showErrorAndDismiss()
            case .empty:
                panel.showEmptyAndDismiss()
            default:
                panel.hide()
            }
        }
        
        sm.onInsertText = { [weak self] text in
            guard let service = self?.textInsertionService else { return false }
            // Returns true if paste was attempted (which maps to .success state in state machine)
            // Returns false if fallback to clipboard occurred (which maps to .copiedToClipboard)
            return service.insertText(text)
        }
        
        sm.onCancel = { [weak self] in
            // Cancel any in-progress transcription
            self?.transcriptionTask?.cancel()
            self?.transcriptionTask = nil
            
            // Stop recording if active
            self?.recordingService?.stopRecording()
            self?.recordingService?.deleteRecording()
            
            self?.notchPanel?.hide()
        }
        
        // MARK: Recording callbacks
        
        sm.onStartRecording = { [weak self] in
            guard let self = self else { return }
            
            // Check microphone permission first (deferred until user actually tries to record)
            guard let pm = self.permissionsManager else { return }
            
            if pm.isMicrophoneGranted {
                // Already granted - start recording immediately
                self.startRecordingInternal()
            } else {
                // Request permission (will show system prompt if first time)
                pm.requestMicrophoneIfNeeded { [weak self] granted in
                    guard let self = self else { return }
                    
                    if granted {
                        // Brief delay after permission grant to let audio subsystem fully initialize
                        // Pattern used by Loop, MacWhisper, and other audio apps
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            self?.startRecordingInternal()
                        }
                    } else {
                        self.logger.warning("Microphone permission denied")
                        self.stateMachine?.send(.transcriptionFailed(error: "Microphone access required. Please enable in System Settings."))
                    }
                }
            }
        }
        
        sm.onStopRecording = { [weak self, weak sm] in
            guard let self = self else { return }
            
            // Stop recording and get audio URL
            guard let audioURL = self.recordingService?.stopRecording() else {
                self.logger.warning("No recording available")
                sm?.send(.transcriptionFailed(error: "No recording available"))
                return
            }
            
            self.logger.debug("Recording stopped, starting transcription...")
            
            // Notify that transcription has started (shows processing state)
            // Brief delay to allow UI to update
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.transcriptionStartedDelay) {
                sm?.send(.transcriptionStarted)
            }
            
            // Start transcription task
            // Capture state machine reference before entering Task for Swift 6 concurrency safety
            let stateMachine = sm
            self.transcriptionTask = Task { [weak self] in
                defer {
                    // Clean up recording file after transcription
                    self?.recordingService?.deleteRecording()
                }
                
                do {
                    let text = try await TranscriptionCoordinator.shared.transcribe(audioURL: audioURL)
                    
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        stateMachine?.send(.transcriptionCompleted(text: text))
                    }
                } catch {
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    self?.logger.error("Transcription failed: \(error.localizedDescription)")
                    await MainActor.run {
                        stateMachine?.send(.transcriptionFailed(error: error.localizedDescription))
                    }
                }
            }
        }
        
        // Observe state changes to update panel visual state
        sm.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .recording:
                    self?.notchPanel?.setVisualState(.recording)
                case .processing:
                    self?.notchPanel?.setVisualState(.processing)
                case .success:
                    self?.playFeedbackAndRestoreVolume { $0.playSuccessSound() }
                    self?.notchPanel?.setVisualState(.success)
                case .copiedToClipboard:
                    self?.playFeedbackAndRestoreVolume { $0.playSuccessSound() }
                    self?.notchPanel?.setVisualState(.copiedToClipboard)
                case .error(_):
                    self?.playFeedbackAndRestoreVolume { $0.playErrorSound() }
                    self?.notchPanel?.setVisualState(.error)
                case .empty:
                    self?.playFeedbackAndRestoreVolume { $0.playEmptySound() }
                    self?.notchPanel?.setVisualState(.empty)
                case .cancelled:
                    // No sound for cancel, just restore
                    self?.audioFeedbackService?.restoreVolume()
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Wire up hotkey service
        hotkeyService?.onHotkeyPressed = { [weak sm, weak self] in
            guard let sm = sm, let self = self else { return }
            
            // Toggle behavior: if recording, stop; otherwise start
            if sm.state == .recording {
                sm.send(.hotkeyPressed)  // This stops recording
            } else if sm.state == .idle {
                // Check accessibility permission before starting (needed for text insertion)
                // This prompts once per version if not granted
                if let pm = self.permissionsManager, !pm.isAccessibilityGranted {
                    self.logger.info("Requesting accessibility permission on first hotkey press...")
                    pm.requestAccessibilityIfNeeded()
                    // Don't block - user can still record, will just get clipboard fallback
                }
                
                sm.send(.hotkeyPressed)  // This starts recording
            }
            // Ignore hotkey in other states (processing, success, etc.)
        }
        
        // Start listening for hotkey
        hotkeyService?.start()
    }
    
    // MARK: - Debug Test Methods
    
    #if DEBUG
    
    /// Tests error flow using mock mode (no real recording/transcription)
    @objc private func testErrorFlow() {
        guard let sm = stateMachine else { return }
        
        // Enable mock mode to prevent real recording
        sm.isMockMode = true
        
        print("[Test] Error: recording → processing → error (mock mode)")
        sm.send(.hotkeyPressed)  // → .recording (no real recording)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
            sm?.send(.stopRecording)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak sm] in
                sm?.send(.transcriptionStarted)  // → .processing
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sm] in
                sm?.send(.transcriptionFailed(error: "Network connection failed"))  // → .error
                // Mock mode auto-disables when state returns to .idle
            }
        }
    }
    
    #endif
    
    // MARK: - Recording Helpers
    
    /// Actually starts recording (called after permission is confirmed).
    private func startRecordingInternal() {
        do {
            try recordingService?.startRecording()
            logger.debug("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            // Trigger error state
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine?.send(.transcriptionFailed(error: error.localizedDescription))
            }
        }
    }
    
    // MARK: - Audio Feedback Helpers
    
    /// Plays a feedback sound and restores volume after a delay.
    private func playFeedbackAndRestoreVolume(_ playSound: (AudioFeedbackService) -> Void) {
        guard let service = audioFeedbackService else { return }
        playSound(service)
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.volumeRestoreDelay) { [weak self] in
            self?.audioFeedbackService?.restoreVolume()
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func openSettings() {
        // Switch to regular activation policy to allow keyboard input
        NSApp.setActivationPolicy(.regular)
        
        // If window already exists, bring it to front properly (boring.notch pattern)
        if let window = settingsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // Create settings window hosting SwiftUI SettingsView
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Open Dictation Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self  // To detect when window closes
        
        settingsWindow = window
        
        // Show window with proper ordering (boring.notch pattern)
        // orderFrontRegardless forces window to front even when app is in accessory mode
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation for reliable focus
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) == settingsWindow else { return }
        
        // Switch back to accessory mode (menu bar only, no Dock icon)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
