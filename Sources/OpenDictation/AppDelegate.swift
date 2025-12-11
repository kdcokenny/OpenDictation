import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
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
    private var overlayPanel: DictationOverlayPanel?
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
        setupStatusItem()
        setupServices()
        setupStateMachine()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Restore volume if still ducked (safety net)
        audioFeedbackService?.restoreVolume()
        overlayPanel?.hide()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Open Dictation")
        
        let menu = NSMenu()
        
        // Debug submenu (only in DEBUG builds)
        #if DEBUG
        let debugMenu = NSMenu(title: "Debug")
        
        let testNormalItem = NSMenuItem(title: "Test: Normal Flow", action: #selector(testNormalFlow), keyEquivalent: "")
        testNormalItem.target = self
        debugMenu.addItem(testNormalItem)
        
        let testFastPathItem = NSMenuItem(title: "Test: Fast Path", action: #selector(testFastPathFlow), keyEquivalent: "")
        testFastPathItem.target = self
        debugMenu.addItem(testFastPathItem)
        
        let testEmptyItem = NSMenuItem(title: "Test: Empty Result", action: #selector(testEmptyResultFlow), keyEquivalent: "")
        testEmptyItem.target = self
        debugMenu.addItem(testEmptyItem)
        
        let testErrorItem = NSMenuItem(title: "Test: Error", action: #selector(testErrorFlow), keyEquivalent: "")
        testErrorItem.target = self
        debugMenu.addItem(testErrorItem)
        
        debugMenu.addItem(NSMenuItem.separator())
        
        let testCancelRecordingItem = NSMenuItem(title: "Test: Cancel Recording", action: #selector(testCancelRecordingFlow), keyEquivalent: "")
        testCancelRecordingItem.target = self
        debugMenu.addItem(testCancelRecordingItem)
        
        let testCancelProcessingItem = NSMenuItem(title: "Test: Cancel Processing", action: #selector(testCancelProcessingFlow), keyEquivalent: "")
        testCancelProcessingItem.target = self
        debugMenu.addItem(testCancelProcessingItem)
        
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        #endif
        
        let settingsItem = NSMenuItem(
            title: "Settings...",
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
        overlayPanel = DictationOverlayPanel()
        textInsertionService = TextInsertionService()
        audioFeedbackService = AudioFeedbackService()
        hotkeyService = HotkeyService()
        recordingService = RecordingService.shared
        
        // Start permission polling
        permissionsManager?.startPolling()
        
        // Log permission status on launch
        if let pm = permissionsManager {
            print("[OpenDictation] Accessibility granted: \(pm.isAccessibilityGranted)")
            print("[OpenDictation] Microphone granted: \(pm.isMicrophoneGranted)")
            print("[OpenDictation] All permissions granted: \(pm.allPermissionsGranted)")
            
            // Request accessibility permission if not granted (triggers system prompt)
            if !pm.isAccessibilityGranted {
                print("[OpenDictation] Requesting Accessibility permission...")
                pm.requestAccessibility()
            }
            
            // Request microphone permission if not granted (async, non-blocking)
            if !pm.isMicrophoneGranted {
                print("[OpenDictation] Requesting Microphone permission...")
                pm.requestMicrophone()
            }
        }
    }
    
    private func setupStateMachine() {
        let sm = DictationStateMachine()
        stateMachine = sm
        
        // Wire up panel callbacks
        overlayPanel?.onEscapePressed = { [weak sm] in
            sm?.send(.escapePressed)
        }
        
        overlayPanel?.onDismissCompleted = { [weak sm] in
            sm?.send(.dismissCompleted)
        }
        
        // Wire up audio level for real-time waveform visualization
        recordingService?.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.overlayPanel?.setAudioLevel(level)
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
            self?.overlayPanel?.show()
        }
        
        sm.onHidePanel = { [weak self, weak sm] in
            guard let self = self, let sm = sm else { return }
            
            switch sm.state {
            case .success:
                self.overlayPanel?.showSuccessAndDismiss()
            case .copiedToClipboard:
                self.overlayPanel?.showClipboardAndDismiss()
            case .error:
                self.overlayPanel?.showErrorAndDismiss()
            case .empty:
                self.overlayPanel?.showEmptyAndDismiss()
            default:
                self.overlayPanel?.hide()
            }
        }
        
        sm.onInsertText = { [weak self] text in
            guard let service = self?.textInsertionService else { return false }
            let result = service.insertOrCopy(text)
            return result == .inserted
        }
        
        sm.onCancel = { [weak self] in
            // Cancel any in-progress transcription
            self?.transcriptionTask?.cancel()
            self?.transcriptionTask = nil
            
            // Stop recording if active
            self?.recordingService?.stopRecording()
            self?.recordingService?.deleteRecording()
            
            self?.overlayPanel?.hide()
        }
        
        // MARK: Recording callbacks
        
        sm.onStartRecording = { [weak self] in
            do {
                try self?.recordingService?.startRecording()
                print("[OpenDictation] Recording started")
            } catch {
                print("[OpenDictation] Failed to start recording: \(error.localizedDescription)")
                // Trigger error state
                DispatchQueue.main.async {
                    self?.stateMachine?.send(.transcriptionFailed(error: error.localizedDescription))
                }
            }
        }
        
        sm.onStopRecording = { [weak self, weak sm] in
            guard let self = self else { return }
            
            // Stop recording and get audio URL
            guard let audioURL = self.recordingService?.stopRecording() else {
                print("[OpenDictation] No recording available")
                sm?.send(.transcriptionFailed(error: "No recording available"))
                return
            }
            
            print("[OpenDictation] Recording stopped, starting transcription...")
            
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
                    let text = try await TranscriptionService.shared.transcribe(audioURL: audioURL)
                    
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        stateMachine?.send(.transcriptionCompleted(text: text))
                    }
                } catch {
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    print("[OpenDictation] Transcription failed: \(error.localizedDescription)")
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
                    self?.overlayPanel?.setVisualState(.recording)
                case .processing:
                    self?.overlayPanel?.setVisualState(.processing)
                case .success:
                    self?.playFeedbackAndRestoreVolume { $0.playSuccessSound() }
                    self?.overlayPanel?.setVisualState(.success)
                case .copiedToClipboard:
                    self?.playFeedbackAndRestoreVolume { $0.playSuccessSound() }
                    self?.overlayPanel?.setVisualState(.copiedToClipboard)
                case .error:
                    self?.playFeedbackAndRestoreVolume { $0.playErrorSound() }
                    self?.overlayPanel?.setVisualState(.error)
                case .empty:
                    // No sound for empty, just restore
                    self?.audioFeedbackService?.restoreVolume()
                    self?.overlayPanel?.setVisualState(.empty)
                case .cancelled:
                    // No sound for cancel, just restore
                    self?.audioFeedbackService?.restoreVolume()
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Wire up hotkey service
        hotkeyService?.onHotkeyPressed = { [weak sm] in
            guard let sm = sm else { return }
            
            // Toggle behavior: if recording, stop; otherwise start
            if sm.state == .recording {
                sm.send(.hotkeyPressed)  // This stops recording
            } else if sm.state == .idle {
                sm.send(.hotkeyPressed)  // This starts recording
            }
            // Ignore hotkey in other states (processing, success, etc.)
        }
        
        // Start listening for hotkey
        hotkeyService?.start()
    }
    
    // MARK: - Debug Test Methods
    
    #if DEBUG
    
    /// Tests normal flow: recording → processing → success → text insertion
    @objc private func testNormalFlow() {
        guard let sm = stateMachine else { return }
        
        print("[Test] Normal Flow: recording → processing → success")
        sm.send(.hotkeyPressed)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak sm] in
            sm?.send(.stopRecording)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak sm] in
                sm?.send(.transcriptionStarted)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
                sm?.send(.transcriptionCompleted(text: "Hello, this is a sample transcription from Open Dictation!"))
            }
        }
    }
    
    /// Tests fast path: recording → immediate success (skips processing animation)
    @objc private func testFastPathFlow() {
        guard let sm = stateMachine else { return }
        
        print("[Test] Fast Path: recording → immediate success (skip processing)")
        sm.send(.hotkeyPressed)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak sm] in
            sm?.send(.stopRecording)
            
            // Complete immediately (within 0.5s threshold) - no transcriptionStarted
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak sm] in
                sm?.send(.transcriptionCompleted(text: "Quick transcription!"))
            }
        }
    }
    
    /// Tests empty result flow: recording → processing → empty (shake animation)
    @objc private func testEmptyResultFlow() {
        guard let sm = stateMachine else { return }
        
        print("[Test] Empty Result: recording → processing → empty (shake)")
        sm.send(.hotkeyPressed)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
            sm?.send(.stopRecording)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak sm] in
                sm?.send(.transcriptionStarted)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sm] in
                sm?.send(.transcriptionCompleted(text: "   ")) // Whitespace only
            }
        }
    }
    
    /// Tests error flow: recording → processing → error (red tint)
    @objc private func testErrorFlow() {
        guard let sm = stateMachine else { return }
        
        print("[Test] Error: recording → processing → error (red tint)")
        sm.send(.hotkeyPressed)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
            sm?.send(.stopRecording)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak sm] in
                sm?.send(.transcriptionStarted)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sm] in
                sm?.send(.transcriptionFailed(error: "Network connection failed"))
            }
        }
    }
    
    /// Tests cancel during recording: recording → escape → cancelled
    @objc private func testCancelRecordingFlow() {
        guard let sm = stateMachine else { return }
        
        print("[Test] Cancel Recording: recording → escape → cancelled")
        sm.send(.hotkeyPressed)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
            sm?.send(.escapePressed)
        }
    }
    
    /// Tests cancel during processing: recording → processing → escape → cancelled
    @objc private func testCancelProcessingFlow() {
        guard let sm = stateMachine else { return }
        
        print("[Test] Cancel Processing: recording → processing → escape → cancelled")
        sm.send(.hotkeyPressed)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sm] in
            sm?.send(.stopRecording)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak sm] in
                sm?.send(.transcriptionStarted)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sm] in
                sm?.send(.escapePressed)
            }
        }
    }
    
    #endif
    
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
        
        // If window already exists, just bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) == settingsWindow else { return }
        
        // Switch back to accessory mode (menu bar only, no Dock icon)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
