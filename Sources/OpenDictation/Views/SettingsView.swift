import SwiftUI
import KeyboardShortcuts

/// Main settings view for Open Dictation.
/// Provides configuration for shortcut, transcription mode, language, and API settings.
/// Model selection is automatic based on system capabilities, with manual override in Advanced.
struct SettingsView: View {
    
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
    
    // MARK: - Computed
    
    private var transcriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: transcriptionModeRaw) ?? .local
    }
    
    // MARK: - Body
    
    var body: some View {
        Form {
            // MARK: Shortcut Section
            Section {
                KeyboardShortcuts.Recorder("Keyboard Shortcut", name: .toggleDictation)
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
                if let progress = modelManager.downloadProgress[modelManager.recommendedModelName] {
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
                    ForEach(Array(WhisperLanguages.all.sorted(by: { $0.value < $1.value })), id: \.key) { code, name in
                        Text(name).tag(code)
                    }
                }
                .onChange(of: language) { _, newLanguage in
                    // Trigger smart model selection when language changes
                    Task {
                        await modelManager.handleLanguageChange(to: newLanguage)
                    }
                }
                
                Text("Language to recognize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // MARK: Local Settings Section (Advanced)
            if transcriptionMode == .local {
                localSettingsSection
            }
            
            // MARK: Cloud Settings Section
            if transcriptionMode == .cloud {
                cloudSettingsSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
        .onAppear {
            loadApiKey()
        }
        .onChange(of: apiKey) { _, newValue in
            saveApiKey(newValue)
        }
    }
    
    // MARK: - Local Settings Section
    
    @ViewBuilder
    private var localSettingsSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $isLocalAdvancedExpanded) {
                AdvancedModelSettingsView(modelManager: modelManager)
                    .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Cloud Settings Section
    
    @ViewBuilder
    private var cloudSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isApiKeyVisible {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { isApiKeyVisible.toggle() }) {
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
                        Text("Default: whisper-1. Groq: whisper-large-v3-turbo")
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
            
            // Reset to automatic button (only show if manual override is active)
            if modelManager.isManualModelOverride {
                Button("Reset to Automatic") {
                    Task {
                        await modelManager.resetToAutomatic()
                    }
                }
                .buttonStyle(.link)
            }
        }
        .alert("Download Model", isPresented: $showDownloadAlert) {
            Button("Download") {
                if let model = modelToDownload {
                    Task {
                        await modelManager.downloadModel(model)
                        // After download, select it
                        if modelManager.isModelDownloaded(model.name) {
                            modelManager.selectedModelName = model.name
                            modelManager.isManualModelOverride = true
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
        modelManager.downloadProgress[modelManager.selectedModelName]
    }
    
    /// Handles model selection, prompting for download if needed
    private func selectModel(_ modelName: String) {
        // If already downloaded, just select it
        if modelManager.isModelDownloaded(modelName) {
            modelManager.selectedModelName = modelName
            modelManager.isManualModelOverride = true
            return
        }
        
        // Need to download - show confirmation
        if let model = PredefinedModels.find(byName: modelName) {
            modelToDownload = model
            showDownloadAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
