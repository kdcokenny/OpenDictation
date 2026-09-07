import AppKit
import SwiftUI
import Combine
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    // MARK: - Logger
    
    private let logger = Logger.app(category: "AppDelegate")
    
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
    private var dictationHistoryService: DictationHistoryService?
    private var audioFeedbackService: AudioFeedbackService?
    private var hotkeyService: HotkeyService?
    private var recordingService: RecordingService?
    private var stateMachine: DictationStateMachine?
    private var settingsWindow: NSWindow?
    private var recentWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var activeHistoryEntryID: UUID?
    private var currentHistoryEntryID: UUID?
    
    /// The session that currently owns the microphone recorder.
    private var recordingSessionID: UUID?

    /// Tasks and files remain keyed by session until their own cleanup finishes.
    /// This prevents an older task from deleting a newer recording.
    private var transcriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var transcriptionAudioURLs: [UUID: URL] = [:]
    private var heldHotkeySessionID: UUID?
    
    /// App activation observer token (for cleanup)
    private var appActivationObserver: NSObjectProtocol?
    
    // MARK: - NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip all app setup when running unit tests (prevents permission pop-ups, status bar icons, etc.)
        if AppEnvironment.isRunningTests {
            return
        }
        
        // MARK: - Accessibility Permission Check
        // Begin the accessibility check before setup. The escape monitor subscribes
        // to permission changes and starts as soon as the event tap can be created.
        permissionsManager = PermissionsManager()
        permissionsManager?.checkAccessibilityOnLaunch()
        
        // MARK: - App Setup
        // Check if app should be moved to Applications (before other setup)
        ApplicationMover.checkAndOfferToMoveToApplications()
        
        setupStatusItem()
        setupServices()
        setupEscapeKeyMonitor()
        setupStateMachine()
        setupLocalTranscription()
        
        // Observe screen configuration changes to rebuild the UI if needed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildNotchUI),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Perform initial UI setup
        rebuildNotchUI()
        
        // Initialize updater (starts automatic update checks)
        _ = UpdateService.shared
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanupAllSessionWork()

        // Remove observers
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Remove app activation observer
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        
        // Restore volume if still ducked (safety net)
        audioFeedbackService?.restoreVolume()
        textInsertionService?.restoreClipboard()
        dictationHistoryService?.cleanupRetainedAudio()
        notchPanel?.destroy()
        notchPanel = nil
        EscapeKeyMonitor.shared.stop()
        EscapeKeyMonitor.shared.onEscapePressed = nil
        EscapeKeyMonitor.shared.shouldHandleEscape = nil
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
        
        let recentItem = NSMenuItem(
            title: "Recent...",
            action: #selector(openRecent),
            keyEquivalent: ""
        )
        recentItem.target = self
        menu.addItem(recentItem)

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
        // PermissionsManager already initialized in applicationDidFinishLaunching
        // to check accessibility on launch
        if permissionsManager == nil {
            permissionsManager = PermissionsManager()
        }
        
        textInsertionService = TextInsertionService()
        dictationHistoryService = DictationHistoryService.shared
        audioFeedbackService = AudioFeedbackService()
        hotkeyService = HotkeyService()
        recordingService = RecordingService.shared
        
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
    
    /// Sets up the singleton escape key monitor.
    /// This monitor lives for the entire app lifetime and is separate from panel lifecycle.
    /// Pattern from NotchDrop's EventMonitors singleton.
    private func setupEscapeKeyMonitor() {
        let monitor = EscapeKeyMonitor.shared
        
        // Wire escape key to state machine
        monitor.onEscapePressed = { [weak self] in
            self?.stateMachine?.send(.escapePressed)
        }
        
        // Only handle escape when dictation is active (state != .idle).
        // Using state machine as source of truth is more robust than window visibility
        // which can desync after window corruption.
        monitor.shouldHandleEscape = { [weak self] in
            return self?.stateMachine?.state != .idle
        }
        
        permissionsManager?.accessibilityDidUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak monitor] in
                guard let self, let monitor else { return }

                if self.permissionsManager?.isAccessibilityGranted == true {
                    monitor.start()
                } else {
                    monitor.stop()
                }
            }
            .store(in: &cancellables)

        if permissionsManager?.isAccessibilityGranted == true {
            monitor.start()
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
            
            // Preserve Whisper's existing upgrade policy only when Whisper is selected.
            let engine = UserDefaults.standard.string(forKey: "localSpeechEngine") ?? "whisper"
            if TranscriptionCoordinator.shared.currentMode == .local && engine == LocalSpeechEngine.whisper.rawValue {
                await ModelManager.shared.checkAndUpgradeIfNeeded()
            }
            await TranscriptionCoordinator.shared.prewarmSelectedLocalModel()
        }
    }
    
    private func setupStateMachine() {
        let sm = DictationStateMachine()
        stateMachine = sm
        
        // Wire up panel callbacks (only if notch panel exists)
        wireNotchPanelCallbacks()
        
        // Wire up audio level for real-time waveform visualization
        recordingService?.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.notchPanel?.setAudioLevel(level)
            }
            .store(in: &cancellables)
        
        // Observe app activation to update context in real-time during recording
        // Single source of truth: state machine holds the context, panel displays it
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let sm = self.stateMachine,
                      sm.state == .recording,
                      !sm.isStopRequested else { return }

                // Update state machine (source of truth)
                let context = ContextDetector.detect()
                sm.currentContext = context

                // Sync to panel display
                self.notchPanel?.setContext(context)
            }
        }
        
        // Wire up state machine callbacks
        sm.onShowPanel = { [weak self, weak sm] sessionID in
            guard let self = self else { return }
            
            // Defensive rebuild if panel is missing or unhealthy (volumeHUD pattern)
            // This recovers from edge cases where the panel becomes stale after sleep/wake
            if self.notchPanel == nil || self.notchPanel?.isHealthy == false {
                self.logger.info("Panel needs rebuild - recreating")
                self.notchPanel?.destroy()
                self.notchPanel = nil
                
                if let screen = NSScreen.findScreenForNotch() {
                    self.notchPanel = NotchOverlayPanel(screen: screen)
                    self.wireNotchPanelCallbacks()
                }
            }
            
            // Fatal: notch screen exists but panel creation failed - unrecoverable
            // Show error dialog and relaunch the app
            if NSScreen.findScreenForNotch() != nil && self.notchPanel == nil {
                self.logger.error("Fatal: notch screen exists but panel is nil - triggering relaunch")
                self.showFatalErrorAndRelaunch()
                return
            }
            
            // Duck other audio first, then play start sound
            // AudioDeviceDuck only affects OTHER audio, our sounds play at full volume
            self.audioFeedbackService?.duckVolume()
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.volumeDuckRampDelay) { [weak self, weak sm] in
                guard sm?.activeSessionID == sessionID,
                      sm?.state == .recording else { return }
                self?.audioFeedbackService?.playStartSound()
            }
            
            // Show panel if available (non-notch Macs get audio feedback only)
            // Pass captured context to the panel for icon display
            if let sm = self.stateMachine {
                self.notchPanel?.setContext(sm.currentContext)
            }
            self.notchPanel?.show()
        }
        
        sm.onHidePanel = { [weak self, weak sm] in
            guard let self = self, let sm = sm else { return }
            
            // Only hide panel if it exists (non-notch Macs skip this)
            guard let panel = self.notchPanel else {
                sm.send(.dismissCompleted)
                return
            }
            
            switch sm.state {
            case .success:
                panel.showSuccessAndDismiss()
            case .copiedToClipboard:
                panel.showClipboardAndDismiss()
            case .error:
                panel.showErrorAndDismiss()
            case .empty:
                panel.showEmptyAndDismiss()
            default:
                panel.hide()
            }
        }
        
        sm.onInsertText = { [weak self] text in
            guard let self = self,
                  let service = self.textInsertionService else {
                return .failed("Text delivery unavailable.")
            }

            let result = service.insertText(text)
            if let entryID = self.activeHistoryEntryID {
                self.dictationHistoryService?.markDelivery(id: entryID, result: result)
            }
            return result
        }
        
        sm.onCancel = { [weak self] sessionID in
            self?.cancelSessionWork(sessionID: sessionID)
        }
        
        // MARK: Recording callbacks
        
        sm.onStartRecording = { [weak self, weak sm] sessionID in
            Task { @MainActor [weak self, weak sm] in
                guard let sm,
                      sm.activeSessionID == sessionID,
                      sm.state == .recording,
                      !sm.isStopRequested else { return }

                let validationError = await TranscriptionCoordinator.shared.validateCurrentMode()

                guard let self,
                      sm.activeSessionID == sessionID,
                      sm.state == .recording,
                      !sm.isStopRequested else { return }

                if let validationError {
                    self.logger.warning("Cannot start dictation: \(validationError)")
                    sm.send(.transcriptionFailed(sessionID: sessionID, error: validationError))
                    return
                }

                self.requestMicrophoneAndStartRecording(
                    sessionID: sessionID,
                    stateMachine: sm
                )
            }
        }

        sm.onStopRecording = { [weak self, weak sm] sessionID in
            guard let self, let sm else { return }

            guard self.recordingSessionID == sessionID else {
                self.logger.debug("Ignoring stop for a session that does not own the recorder")
                return
            }

            self.recordingSessionID = nil
            
            // Stop recording and get audio URL
            guard let audioURL = self.recordingService?.stopRecording() else {
                self.logger.warning("No recording available")
                sm.send(.transcriptionFailed(sessionID: sessionID, error: "No recording available"))
                return
            }
            
            let context = sm.currentContext
            let historyEntryID = self.dictationHistoryService?.createEntry(
                audioURL: audioURL,
                context: context
            )
            self.currentHistoryEntryID = historyEntryID

            self.logger.debug("Recording stopped, starting transcription...")
            
            // Notify that transcription has started (shows processing state)
            // Brief delay to allow UI to update
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.transcriptionStartedDelay) {
                sm.send(.transcriptionStarted(sessionID: sessionID))
            }
            
            // Start transcription task
            // Capture state machine reference before entering Task for Swift 6 concurrency safety
            self.transcriptionAudioURLs[sessionID] = audioURL
            let stateMachine = sm
            self.transcriptionTasks[sessionID] = Task { [weak self] in
                defer {
                    self?.finishTranscriptionWork(sessionID: sessionID, audioURL: audioURL)
                }
                
                do {
                    // Capture state machine reference again inside Task if needed, but it's captured outside
                    let text = try await TranscriptionCoordinator.shared.transcribe(audioURL: audioURL, context: context)
                    
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        guard stateMachine.activeSessionID == sessionID else { return }

                        if let historyEntryID {
                            self?.dictationHistoryService?.markTranscriptionSucceeded(
                                id: historyEntryID,
                                text: text
                            )
                            self?.currentHistoryEntryID = nil
                            self?.activeHistoryEntryID = historyEntryID
                        }
                        stateMachine.send(.transcriptionCompleted(sessionID: sessionID, text: text))
                        self?.activeHistoryEntryID = nil
                    }
                } catch {
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    self?.logger.error("Transcription failed: \(error.localizedDescription)")
                    await MainActor.run {
                        guard stateMachine.activeSessionID == sessionID else { return }

                        if let historyEntryID {
                            self?.dictationHistoryService?.markTranscriptionFailed(
                                id: historyEntryID,
                                message: error.localizedDescription
                            )
                            self?.currentHistoryEntryID = nil
                        }
                        stateMachine.send(.transcriptionFailed(
                            sessionID: sessionID,
                            error: error.localizedDescription
                        ))
                    }
                }
            }
        }

        recordingService?.onRecordingError = { [weak self, weak sm] error, audioURL in
            guard let self,
                  let sm,
                  let sessionID = sm.activeSessionID,
                  self.recordingSessionID == sessionID else { return }

            self.recordingSessionID = nil
            if let audioURL {
                self.recordingService?.deleteRecording(at: audioURL)
            }
            sm.send(.transcriptionFailed(sessionID: sessionID, error: error.localizedDescription))
        }
        
        // Observe state changes to update panel visual state
        sm.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak sm] state in
                guard let self, let sm else { return }
                let sessionID = sm.activeSessionID

                switch state {
                case .recording:
                    self.notchPanel?.setVisualState(.recording)
                case .processing:
                    self.notchPanel?.setVisualState(.processing)
                case .success:
                    self.playFeedbackAndRestoreVolume(sessionID: sessionID, stateMachine: sm) {
                        $0.playSuccessSound()
                    }
                    self.notchPanel?.setVisualState(.success)
                case .copiedToClipboard:
                    self.playFeedbackAndRestoreVolume(sessionID: sessionID, stateMachine: sm) {
                        $0.playSuccessSound()
                    }
                    self.notchPanel?.setVisualState(.copiedToClipboard)
                case .error:
                    self.playFeedbackAndRestoreVolume(sessionID: sessionID, stateMachine: sm) {
                        $0.playErrorSound()
                    }
                    self.notchPanel?.setVisualState(.error)
                case .empty:
                    self.playFeedbackAndRestoreVolume(sessionID: sessionID, stateMachine: sm) {
                        $0.playEmptySound()
                    }
                    self.notchPanel?.setVisualState(.empty)
                case .cancelled:
                    // No sound for cancel, just restore
                    self.audioFeedbackService?.restoreVolume()
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Wire up hotkey service
        hotkeyService?.onHotkeyPressed = { [weak self, weak sm] in
            guard let self, let sm else { return }
            self.handleHotkeyPressed(stateMachine: sm)
        }

        hotkeyService?.onHotkeyReleased = { [weak self, weak sm] in
            guard let self, let sm else { return }
            self.handleHotkeyReleased(stateMachine: sm)
        }
        
        // Start listening for hotkey
        hotkeyService?.start()
    }

    private func handleHotkeyPressed(stateMachine: DictationStateMachine) {
        guard let hotkeyService else { return }

        switch hotkeyService.activationMode {
        case .toggle:
            heldHotkeySessionID = nil
            handleToggleHotkey(stateMachine: stateMachine)

        case .hold:
            guard stateMachine.state == .idle else { return }

            stateMachine.send(.hotkeyPressed(context: ContextDetector.detect()))
            heldHotkeySessionID = stateMachine.activeSessionID
        }
    }

    private func handleHotkeyReleased(stateMachine: DictationStateMachine) {
        guard hotkeyService?.activationMode == .hold,
              let sessionID = heldHotkeySessionID else { return }

        heldHotkeySessionID = nil
        guard stateMachine.activeSessionID == sessionID,
              stateMachine.state == .recording,
              !stateMachine.isStopRequested else { return }

        stopOrCancelRecording(stateMachine: stateMachine, sessionID: sessionID)
    }

    private func handleToggleHotkey(stateMachine: DictationStateMachine) {
        switch stateMachine.state {
        case .idle:
            stateMachine.send(.hotkeyPressed(context: ContextDetector.detect()))

        case .recording:
            guard let sessionID = stateMachine.activeSessionID,
                  !stateMachine.isStopRequested else { return }
            stopOrCancelRecording(stateMachine: stateMachine, sessionID: sessionID)

        default:
            break
        }
    }

    private func stopOrCancelRecording(
        stateMachine: DictationStateMachine,
        sessionID: UUID
    ) {
        guard recordingSessionID == sessionID else {
            // The key was released while microphone permission or startup was pending.
            stateMachine.send(.escapePressed)
            return
        }

        stateMachine.send(.hotkeyPressed(context: ContextDetector.detect()))
    }
    
    // MARK: - Debug Test Methods
    
    #if DEBUG
    
    /// Tests error flow using mock mode (no real recording/transcription)
    @objc private func testErrorFlow() {
        guard let sm = stateMachine else { return }
        
        // Enable mock mode to prevent real recording
        sm.isMockMode = true
        
        print("[Test] Error: recording → processing → error (mock mode)")
        sm.send(.hotkeyPressed(context: .prose))  // → .recording (no real recording)
        guard let sessionID = sm.activeSessionID else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
            sm?.send(.stopRecording(context: .prose))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak sm] in
                sm?.send(.transcriptionStarted(sessionID: sessionID))  // → .processing
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sm] in
                sm?.send(.transcriptionFailed(
                    sessionID: sessionID,
                    error: "Network connection failed"
                ))  // → .error
                // Mock mode auto-disables when state returns to .idle
            }
        }
    }
    
    #endif
    
    // MARK: - Panel Callbacks
    
    /// Wires up notch panel callbacks to the state machine.
    /// Extracted to a method so it can be re-called after panel recreation during screen changes.
    /// Note: Escape key is handled by EscapeKeyMonitor singleton, not panel callbacks.
    private func wireNotchPanelCallbacks() {
        guard let sm = stateMachine else { return }
        
        notchPanel?.onDismissCompleted = { [weak sm, weak self] in
            // Restore after the target app has had the dismissal animation to
            // consume its paste event. TextInsertionService also has a timer fallback.
            self?.textInsertionService?.restoreClipboard()
            
            sm?.send(.dismissCompleted)
        }
    }
    
    // MARK: - Screen Change Handling
    
    /// Rebuilds the notch UI from scratch.
    ///
    /// This method follows the stateless "destroy and recreate" pattern from NotchDrop.
    /// It's called on app launch and any time screen parameters change.
    ///
    /// Display changes are treated as system-level interruptions (not user cancellations),
    /// so we perform immediate cleanup and force state reset.
    @objc private func rebuildNotchUI() {
        // 1. Handle active sessions (display change interrupts recording/processing)
        if stateMachine?.state != .idle {
            logger.info("Screen change interrupted active session - performing emergency cleanup")

            if let sessionID = stateMachine?.activeSessionID {
                cancelSessionWork(sessionID: sessionID)
            }
            textInsertionService?.restoreClipboard()
            
            // Restore audio volume
            audioFeedbackService?.restoreVolume()
            
            // Play error sound for user feedback (something unexpected happened)
            audioFeedbackService?.playErrorSound()
            
            // Destroy panel immediately (no animation needed for system events)
            notchPanel?.destroy()
            notchPanel = nil
            
            // Force state machine back to idle via emergency reset
            // This bypasses normal state transitions since display changes are system-level interruptions
            stateMachine?.send(.forceReset)
        } else {
            // 2. Normal rebuild (no active session)
            notchPanel?.destroy()
            notchPanel = nil
        }
        
        // 3. Find the correct screen and recreate the panel
        if let screen = NSScreen.findScreenForNotch() {
            logger.info("Notch screen found, rebuilding UI.")
            notchPanel = NotchOverlayPanel(screen: screen)
            wireNotchPanelCallbacks() // Re-wire callbacks to the new panel instance
        } else {
            logger.info("No notch screen found, UI will not be shown.")
        }
    }
    
    // MARK: - Recording Helpers

    private func requestMicrophoneAndStartRecording(
        sessionID: UUID,
        stateMachine: DictationStateMachine
    ) {
        guard stateMachine.activeSessionID == sessionID,
              stateMachine.state == .recording,
              !stateMachine.isStopRequested else { return }

        guard let permissionsManager else {
            stateMachine.send(.transcriptionFailed(
                sessionID: sessionID,
                error: "Permission service unavailable."
            ))
            return
        }

        if permissionsManager.isMicrophoneGranted {
            startRecordingInternal(sessionID: sessionID)
            return
        }

        permissionsManager.requestMicrophoneIfNeeded { [weak self, weak stateMachine] granted in
            guard let self,
                  let stateMachine,
                  stateMachine.activeSessionID == sessionID,
                  stateMachine.state == .recording,
                  !stateMachine.isStopRequested else { return }

            guard granted else {
                self.logger.warning("Microphone permission denied")
                stateMachine.send(.transcriptionFailed(
                    sessionID: sessionID,
                    error: "Microphone access required. Please enable in System Settings."
                ))
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak stateMachine] in
                guard let stateMachine,
                      stateMachine.activeSessionID == sessionID,
                      stateMachine.state == .recording,
                      !stateMachine.isStopRequested else { return }
                self?.startRecordingInternal(sessionID: sessionID)
            }
        }
    }
    
    /// Actually starts recording (called after permission is confirmed).
    private func startRecordingInternal(sessionID: UUID) {
        guard stateMachine?.activeSessionID == sessionID,
              stateMachine?.state == .recording,
              stateMachine?.isStopRequested == false else { return }

        guard let recordingService else {
            stateMachine?.send(.transcriptionFailed(
                sessionID: sessionID,
                error: "Recording service unavailable."
            ))
            return
        }

        do {
            try recordingService.startRecording()
            recordingSessionID = sessionID
            logger.debug("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            stateMachine?.send(.transcriptionFailed(
                sessionID: sessionID,
                error: error.localizedDescription
            ))
        }
    }

    private func cancelSessionWork(sessionID: UUID) {
        transcriptionTasks[sessionID]?.cancel()
        heldHotkeySessionID = nil
        discardCurrentHistoryEntry()

        guard recordingSessionID == sessionID else { return }

        recordingSessionID = nil
        if let audioURL = recordingService?.stopRecording() {
            recordingService?.deleteRecording(at: audioURL)
        }
    }

    private func finishTranscriptionWork(sessionID: UUID, audioURL: URL) {
        recordingService?.deleteRecording(at: audioURL)
        transcriptionAudioURLs[sessionID] = nil
        transcriptionTasks[sessionID] = nil
    }

    private func cleanupAllSessionWork() {
        recordingService?.onRecordingError = nil
        hotkeyService?.onHotkeyPressed = nil
        hotkeyService?.onHotkeyReleased = nil

        for task in transcriptionTasks.values {
            task.cancel()
        }

        if let audioURL = recordingService?.stopRecording() {
            recordingService?.deleteRecording(at: audioURL)
        }

        for audioURL in transcriptionAudioURLs.values {
            recordingService?.deleteRecording(at: audioURL)
        }

        recordingSessionID = nil
        heldHotkeySessionID = nil
        transcriptionTasks.removeAll()
        transcriptionAudioURLs.removeAll()
        discardCurrentHistoryEntry()
        stateMachine?.send(.forceReset)
    }
    
    // MARK: - Audio Feedback Helpers
    
    /// Plays a feedback sound and restores volume after a delay.
    private func playFeedbackAndRestoreVolume(
        sessionID: UUID?,
        stateMachine: DictationStateMachine,
        _ playSound: (AudioFeedbackService) -> Void
    ) {
        guard let service = audioFeedbackService else { return }
        playSound(service)

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.volumeRestoreDelay) { [weak self, weak stateMachine] in
            if let activeSessionID = stateMachine?.activeSessionID,
               activeSessionID != sessionID {
                return
            }
            self?.audioFeedbackService?.restoreVolume()
        }
    }

    private func discardCurrentHistoryEntry() {
        if let entryID = currentHistoryEntryID {
            dictationHistoryService?.discardEntry(id: entryID)
            currentHistoryEntryID = nil
        }

        if let entryID = activeHistoryEntryID {
            dictationHistoryService?.discardEntry(id: entryID)
            activeHistoryEntryID = nil
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
        window.setContentSize(SettingsView.windowSize)
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
    
    @objc private func openRecent() {
        NSApp.setActivationPolicy(.regular)

        if let window = recentWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let history = dictationHistoryService ?? DictationHistoryService.shared
        dictationHistoryService = history
        let recentView = RecentDictationsView(history: history)
        let hostingController = NSHostingController(rootView: recentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Recent"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.minSize = NSSize(width: 420, height: 320)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        recentWindow = window

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              closedWindow == settingsWindow || closedWindow == recentWindow else { return }

        if closedWindow == settingsWindow {
            settingsWindow = nil
        }
        if closedWindow == recentWindow {
            recentWindow = nil
        }
        
        // Switch back to accessory mode (menu bar only, no Dock icon)
        DispatchQueue.main.async {
            if self.settingsWindow == nil && self.recentWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Error Recovery
    
    /// Relaunches the application after a fatal error.
    /// Pattern from Karabiner-Elements Relauncher.swift
    private func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if error == nil {
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }
    
    /// Opens GitHub issue page with pre-populated bug report.
    /// Pattern from DockDoor/Stats bug reporting.
    private func openBugReport() {
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        let body = """
        ## Description
        The notch panel failed to recover after automatic rebuild attempt.
        
        ## Environment
        - macOS version: \(macOSVersion)
        - App version: \(appVersion)
        
        ## Steps before issue occurred
        1. 
        
        ## Additional context
        
        """
        
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://github.com/kdcokenny/OpenDictation/issues/new?labels=bug&title=Bug%3A%20Notch%20panel%20failed%20to%20recover&body=\(encodedBody)"
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Shows fatal error alert and relaunches the app.
    /// Called when the notch panel fails to recover.
    private func showFatalErrorAndRelaunch() {
        logger.error("Fatal: Failed to create notch panel - showing recovery dialog")
        
        let alert = NSAlert()
        alert.messageText = "Open Dictation Error"
        alert.informativeText = "The app encountered an unrecoverable error and will restart automatically."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Report Issue")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            openBugReport()
        }
        
        relaunchApp()
    }
}
