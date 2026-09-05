import SwiftUI
import KeyboardShortcuts
import Sparkle
import LaunchAtLogin

/// Main settings view for Open Dictation.
/// Provides configuration for shortcut, transcription mode, language, and API settings.
/// Model selection is automatic based on system capabilities, with manual override in Advanced.
struct SettingsView: View {
    static let windowSize = NSSize(width: 540, height: 700)
    
    // MARK: - Static Helpers
    
    /// Returns the system language code if Whisper supports it, otherwise "" (auto-detect).
    private static var systemLanguageCode: String {
        guard let preferred = Locale.preferredLanguages.first else {
            return ""  // auto-detect
        }
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? ""
        // Return code if Whisper supports it, otherwise auto-detect
        return WhisperLanguages.all.keys.contains(code) ? code : ""
    }
    
    // MARK: - State
    
    /// Transcription mode (local/cloud)
    @AppStorage("transcriptionMode") private var transcriptionModeRaw: String = TranscriptionMode.local.rawValue
    
    /// Language setting - used by both local and cloud modes
    /// Defaults to system language if supported, otherwise auto-detect
    @AppStorage("language") private var language: String = SettingsView.systemLanguageCode
    
    /// API key stored in Keychain (not @AppStorage for security)
    @State private var apiKey: String = ""
    @State private var isApiKeyVisible: Bool = false
    
    /// Cloud settings
    @AppStorage("baseURL") private var baseURL: String = "https://api.openai.com/v1"
    @AppStorage("model") private var cloudModel: String = "whisper-1"
    @AppStorage("temperature") private var cloudTemperature: Double = 0.0
    
    /// Controls section expansion
    @State private var isCloudAdvancedExpanded: Bool = false
    @State private var isLocalAdvancedExpanded: Bool = false
    
    /// Model manager for download state
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var parakeetModels = ParakeetModelManager.shared
    @StateObject private var microphones = AudioInputDeviceManager.shared
    @AppStorage("localSpeechEngine") private var localEngineRaw = LocalSpeechEngine.whisper.rawValue
    @AppStorage("dictationActivationMode") private var activationMode = DictationActivationMode.toggle.rawValue
    @AppStorage("inputDeviceUID") private var inputDeviceUID = ""
    @State private var downloadTask: Task<Void, Never>?
    @State private var parakeetDownloadError: String?
    
    // MARK: - Computed
    
    private var transcriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: transcriptionModeRaw) ?? .local
    }
    
    private var localEngine: LocalSpeechEngine {
        LocalSpeechEngine(rawValue: localEngineRaw) ?? .whisper
    }

    private var languageChoices: [String: String] {
        var choices = WhisperLanguages.all
        choices["mt"] = "Maltese"
        return choices
    }

    // MARK: - Body
    
    var body: some View {
        Form {
            Section("Recording") {
                KeyboardShortcuts.Recorder("Keyboard Shortcut", name: .toggleDictation)
                Picker("Activation", selection: $activationMode) {
                    Text("Press to start / stop").tag(DictationActivationMode.toggle.rawValue)
                    Text("Hold to talk").tag(DictationActivationMode.hold.rawValue)
                }
                Picker("Microphone", selection: $inputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(microphones.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    if !inputDeviceUID.isEmpty && microphones.device(withUID: inputDeviceUID) == nil {
                        Text("Unavailable microphone").tag(inputDeviceUID)
                    }
                }
                if !inputDeviceUID.isEmpty && microphones.device(withUID: inputDeviceUID) == nil {
                    Text("Reconnect your selected microphone or choose another input.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Refresh Microphones") { microphones.refresh() }
                LaunchAtLogin.Toggle("Launch at Login")
            }

            // MARK: Transcription Mode Section
            Section {
                Picker("Mode", selection: Binding(
                    get: { transcriptionMode },
                    set: { transcriptionModeRaw = $0.rawValue }
                )) {
                    ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                // Show inline download progress when downloading recommended model
                if transcriptionMode == .local, localEngine == .whisper,
                   let progress = modelManager.downloadProgress[modelManager.recommendedModelName] {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                } else {
                    Text(transcriptionMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // MARK: Language Section (Universal - used by both modes)
            Section {
                Picker("Language", selection: $language) {
                    ForEach(Array(languageChoices.sorted(by: { $0.value < $1.value })), id: \.key) { code, name in
                        Text(name).tag(code)
                    }
                }
                .onChange(of: language) { _, newLanguage in
                    // Trigger smart model selection when language changes
                    Task {
                        if transcriptionMode == .local && localEngine == .whisper {
                            await modelManager.handleLanguageChange(to: newLanguage)
                        }
                        await TranscriptionCoordinator.shared.prewarmSelectedLocalModel()
                    }
                }
                
                if transcriptionMode == .local && !localEngine.supportsLanguage(language) {
                    Text("Choose an engine that supports this language.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if transcriptionMode == .local && localEngine == .parakeetV3 {
                    Text("Parakeet v3 recognizes 25 European languages. The language selection is a hint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // MARK: Local Settings Section (Advanced)
            if transcriptionMode == .local {
                localSettingsSection
            }
            
            // MARK: Cloud Settings Section
            if transcriptionMode == .cloud {
                cloudSettingsSection
            }
            
            DictionarySettingsView()
            UpdatesSettingsSection()
        }
        .formStyle(.grouped)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear {
            microphones.refresh()
            if language.isEmpty { language = "auto" }
            // Only load API key if already in cloud mode (rare - user changed mode previously)
            if transcriptionMode == .cloud {
                loadApiKey()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphones.refresh()
        }
        .onChange(of: localEngineRaw) { _, _ in
            parakeetDownloadError = nil
            Task { await TranscriptionCoordinator.shared.prewarmSelectedLocalModel() }
        }
        .onChange(of: transcriptionModeRaw) { _, newValue in
            // Load API key when user switches to cloud mode
            if TranscriptionMode(rawValue: newValue) == .cloud {
                loadApiKey()
            }
            Task { await TranscriptionCoordinator.shared.prewarmSelectedLocalModel() }
        }
        .onChange(of: apiKey, initial: false) { _, newValue in
            // Save API key changes (initial: false prevents firing on load)
            saveApiKey(newValue)
        }
    }
    
    // MARK: - Local Settings Section
    
    @ViewBuilder
    private var localSettingsSection: some View {
        Section("On-device speech") {
            Picker("Engine", selection: $localEngineRaw) {
                ForEach(LocalSpeechEngine.allCases, id: \.rawValue) { engine in
                    Text(engine.displayName).tag(engine.rawValue)
                }
            }
            .disabled(downloadTask != nil)
            if let version = localEngine.parakeetVersion {
                parakeetSettings(version)
            } else {
                DisclosureGroup("Whisper Models", isExpanded: $isLocalAdvancedExpanded) {
                    AdvancedModelSettingsView(modelManager: modelManager)
                        .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func parakeetSettings(_ version: ParakeetModelVersion) -> some View {
        if parakeetModels.readiness[version] == .downloading {
            ProgressView(value: parakeetModels.downloadProgress[version] ?? 0)
            Text("Downloading and preparing the model…")
                .font(.caption)
            Button("Cancel Download") { parakeetModels.cancelPreparation(version) }
        } else {
            if parakeetModels.isDownloaded(version) {
                Label("Downloaded · works offline", systemImage: "checkmark.circle")
                    .font(.caption)
            } else {
                Text("Download the model once to use it on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = parakeetModels.lastError[version] {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let error = parakeetDownloadError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !parakeetModels.isDownloaded(version) || parakeetModels.lastError[version] != nil {
                Button("Download and Prepare Model") {
                    parakeetDownloadError = nil
                    downloadTask = Task {
                        do {
                            try await parakeetModels.prepare(version)
                            await TranscriptionCoordinator.shared.prewarmSelectedLocalModel()
                        } catch is CancellationError {
                            // Cancellation leaves the model available for a later retry.
                        } catch {
                            parakeetDownloadError = error.localizedDescription
                        }
                        downloadTask = nil
                    }
                }
            }
        }
        Link("Model licenses and attribution", destination: URL(string: "https://github.com/kdcokenny/OpenDictation/blob/main/THIRD_PARTY_NOTICES.md")!)
            .font(.caption)
    }

    // MARK: - Cloud Settings Section
    
    @ViewBuilder
    private var cloudSettingsSection: some View {
        Section("Cloud service") {
            Menu("Use a Preset") {
                ForEach(CloudTranscriptionPreset.allCases) { preset in
                    Button(preset.name) {
                        baseURL = preset.baseURL
                        cloudModel = preset.model
                        cloudTemperature = 0
                    }
                }
            }
            Text("\(cloudModel) · audio is sent to your configured service")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isApiKeyVisible {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button {
                        isApiKeyVisible.toggle()
                    } label: {
                        Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isApiKeyVisible ? "Hide API Key" : "Show API Key")
                }
                
                Text("From your transcription service")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        // Advanced Cloud Settings
        Section {
            DisclosureGroup("Advanced", isExpanded: $isCloudAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    // Base URL
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Base URL", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                        Text("For Groq: https://api.groq.com/openai/v1")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Model
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Model", text: $cloudModel)
                            .textFieldStyle(.roundedBorder)
                        Text("Use a preset or enter your service's model name.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Temperature Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", cloudTemperature))
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                        }
                        Slider(value: $cloudTemperature, in: 0...1, step: 0.1)
                            .disabled(CloudTranscriptionConfiguration.isGPTTranscribe(cloudModel))
                        Text("0 = deterministic, 1 = more variation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadApiKey() {
        apiKey = KeychainService.shared.load(KeychainService.Key.apiKey) ?? ""
    }
    
    private func saveApiKey(_ value: String) {
        if value.isEmpty {
            KeychainService.shared.delete(KeychainService.Key.apiKey)
        } else {
            KeychainService.shared.save(value, for: KeychainService.Key.apiKey)
        }
    }
}

// MARK: - Advanced Model Settings View

/// Advanced settings for manual model selection.
/// Shows current model, recommended model, and allows manual override.
struct AdvancedModelSettingsView: View {
    @ObservedObject var modelManager: ModelManager
    
    /// Current language setting (to check model compatibility)
    @AppStorage("language") private var language: String = ""
    
    /// Alert for download confirmation
    @State private var showDownloadAlert = false
    @State private var modelToDownload: WhisperModel?
    @State private var downloadError: String?
    
    /// Whether current model supports selected language
    private var isModelCompatible: Bool {
        modelManager.currentModelSupportsLanguage(language)
    }
    
    /// Display name for current language
    private var languageDisplayName: String {
        WhisperLanguages.all[language] ?? language
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Language compatibility warning (only show in manual override mode)
            if modelManager.isManualModelOverride && !isModelCompatible {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .imageScale(.small)
                    Text("This model doesn't support \(languageDisplayName)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
            }
            
            // Current model info
            HStack {
                Text("Current")
                    .foregroundColor(.secondary)
                Spacer()
                Text(modelManager.selectedModelName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            
            // Recommended model info
            HStack {
                Text("Recommended")
                    .foregroundColor(.secondary)
                Spacer()
                Text(modelManager.recommendedModelName)
                    .font(.system(.body, design: .monospaced))
                if modelManager.isUsingRecommendedModel {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.small)
                }
            }
            
            Divider()
            
            // Model picker - shows actual model names for power users
            Picker("Model", selection: Binding(
                get: { modelManager.selectedModelName },
                set: { newModel in
                    selectModel(newModel)
                }
            )) {
                ForEach(PredefinedModels.all, id: \.name) { model in
                    HStack {
                        Text(model.name)
                            .font(.system(.body, design: .monospaced))
                        Text("(\(model.size))")
                            .foregroundColor(.secondary)
                        if modelManager.isModelDownloaded(model.name) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .imageScale(.small)
                        }
                    }
                    .tag(model.name)
                }
            }
            .pickerStyle(.menu)
            
            // Download progress or status
            if let progress = currentDownloadProgress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let downloadError {
                Text(downloadError).font(.caption).foregroundStyle(.red)
            }

            // Reset to automatic button (only show if manual override is active)
            if modelManager.isManualModelOverride {
                Button("Reset to Automatic") {
                    Task {
                        await modelManager.resetToAutomatic()
                        await TranscriptionCoordinator.shared.prewarmSelectedLocalModel()
                    }
                }
                .buttonStyle(.link)
            }
        }
        .alert("Download Model", isPresented: $showDownloadAlert) {
            Button("Download") {
                if let model = modelToDownload {
                    Task {
                        downloadError = nil
                        do {
                            try await modelManager.downloadModel(model)
                            modelManager.selectedModelName = model.name
                            modelManager.isManualModelOverride = true
                            await TranscriptionCoordinator.shared.prewarmSelectedLocalModel()
                        } catch {
                            downloadError = error.localizedDescription
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                modelToDownload = nil
            }
        } message: {
            if let model = modelToDownload {
                Text("Download \(model.displayName)? This requires \(model.size) of storage.")
            }
        }
    }
    
    /// Current download progress for selected model, if any
    private var currentDownloadProgress: Double? {
        let name = modelToDownload?.name ?? modelManager.selectedModelName
        return modelManager.downloadProgress[name]
    }
    
    /// Handles model selection, prompting for download if needed
    private func selectModel(_ modelName: String) {
        // If already downloaded, just select it
        if modelManager.isModelDownloaded(modelName) {
            modelManager.selectedModelName = modelName
            modelManager.isManualModelOverride = true
            Task { await TranscriptionCoordinator.shared.prewarmSelectedLocalModel() }
            return
        }
        
        // Need to download - show confirmation
        if let model = PredefinedModels.find(byName: modelName) {
            modelToDownload = model
            showDownloadAlert = true
        }
    }
}

// MARK: - Updates Settings Section

/// Settings section for automatic updates.
/// Pattern from QuickRecorder/boring.notch - minimal @State with onChange sync.
struct UpdatesSettingsSection: View {
    private let updater: SPUUpdater
    
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    @ObservedObject private var updateService = UpdateService.shared
    
    init() {
        self.updater = UpdateService.shared.updater
        self._automaticallyChecksForUpdates = State(initialValue: UpdateService.shared.updater.automaticallyChecksForUpdates)
        self._automaticallyDownloadsUpdates = State(initialValue: UpdateService.shared.updater.automaticallyDownloadsUpdates)
    }
    
    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }
            
            Toggle("Automatically download and install", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
            
            HStack {
                Button("Check Now") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
                
                Spacer()
                
                Text(versionString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (build \(build))"
    }
}

#Preview {
    SettingsView()
}
