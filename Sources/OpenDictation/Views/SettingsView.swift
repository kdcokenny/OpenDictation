import SwiftUI
import KeyboardShortcuts

/// Main settings view for Open Dictation.
/// Provides configuration for shortcut, transcription mode, quality, language, and API settings.
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
    
    /// Transcription quality (local mode)
    @AppStorage("transcriptionQuality") private var qualityRaw: String = TranscriptionQuality.fast.rawValue
    
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
    
    /// Model manager for download state
    @StateObject private var modelManager = ModelManager.shared
    
    /// Download state
    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0
    
    /// Alert state for download prompt
    @State private var showDownloadAlert: Bool = false
    
    /// Track previous values to revert on cancel
    @State private var previousQualityRaw: String = ""
    @State private var previousLanguage: String = ""
    
    /// Whether download was triggered by mode switch (vs quality/language change)
    @State private var isModeSwitchTrigger: Bool = false
    
    // MARK: - Computed
    
    private var transcriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: transcriptionModeRaw) ?? .local
    }
    
    private var quality: TranscriptionQuality {
        TranscriptionQuality(rawValue: qualityRaw) ?? .fast
    }
    
    /// The model needed for current quality + language
    private var requiredModel: WhisperModel? {
        PredefinedModels.model(for: quality, language: language)
    }
    
    /// Whether the required model is downloaded
    private var isModelReady: Bool {
        guard let model = requiredModel else { return false }
        return modelManager.isDownloaded(model)
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
                
                // Show inline download progress when downloading
                if let model = requiredModel,
                   let progress = modelManager.downloadProgress[model.name] {
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
                
                Text("Language to recognize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // MARK: Local Settings Section
            if transcriptionMode == .local {
                localSettingsSection
            }
            
            // MARK: Cloud Settings Section
            if transcriptionMode == .cloud {
                cloudSettingsSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 480)
        .onAppear {
            loadApiKey()
            updateSelectedModel()
        }
        .onChange(of: apiKey) { _, newValue in
            saveApiKey(newValue)
        }
        .onChange(of: qualityRaw) { oldValue, newValue in
            updateSelectedModel()
            // When switching quality tiers, check if new model needs download
            if transcriptionMode == .local && !isModelReady {
                previousQualityRaw = oldValue
                isModeSwitchTrigger = false
                showDownloadAlert = true
            }
        }
        .onChange(of: language) { oldValue, newValue in
            updateSelectedModel()
            // When changing language, check if new model needs download
            if transcriptionMode == .local && !isModelReady {
                previousLanguage = oldValue
                isModeSwitchTrigger = false
                showDownloadAlert = true
            }
        }
        .onChange(of: transcriptionModeRaw) { oldValue, newValue in
            // When switching to Local, check if model is ready
            if newValue == TranscriptionMode.local.rawValue && !isModelReady {
                isModeSwitchTrigger = true
                showDownloadAlert = true
            }
        }
        .alert("Download Model", isPresented: $showDownloadAlert) {
            Button("Download") {
                startDownload()
            }
            Button(isModeSwitchTrigger ? "Use Online" : "Cancel", role: .cancel) {
                revertChanges()
            }
        } message: {
            if let model = requiredModel {
                Text("This model requires \(model.size) of storage.")
            } else {
                Text("A speech model is required for offline transcription.")
            }
        }
    }
    
    // MARK: - Local Settings Section
    
    @ViewBuilder
    private var localSettingsSection: some View {
        // Quality Section
        Section {
            ForEach(TranscriptionQuality.allCases, id: \.self) { tier in
                qualityRow(tier)
            }
        } header: {
            Text("Quality")
                .font(.headline)
        }
    }
    
    // MARK: - Quality Row
    
    @ViewBuilder
    private func qualityRow(_ tier: TranscriptionQuality) -> some View {
        let isSelected = quality == tier
        let modelName = tier.modelName(forLanguage: language)
        let isDownloaded = modelManager.downloadedModels.contains { $0.name == modelName }
        let isDownloading = modelManager.downloadProgress[modelName] != nil
        
        HStack {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .imageScale(.large)
            
            // Quality info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tier.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    if tier.isBundled {
                        Text("Included")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                Text(tier.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator (consistent sizing)
            if isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else if !isDownloaded && !tier.isBundled {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            qualityRaw = tier.rawValue
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
    
    private func updateSelectedModel() {
        // Update the selected model in ModelManager based on quality + language
        if let model = requiredModel {
            modelManager.selectedModelName = model.name
        }
    }
    
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
    
    private func startDownload() {
        guard let model = requiredModel else { return }
        Task {
            await modelManager.downloadModel(model)
        }
        // Clear revert state since user chose to download
        previousQualityRaw = ""
        previousLanguage = ""
    }
    
    private func revertChanges() {
        if isModeSwitchTrigger {
            // Revert mode switch
            transcriptionModeRaw = TranscriptionMode.cloud.rawValue
        } else if !previousQualityRaw.isEmpty {
            // Revert quality change
            qualityRaw = previousQualityRaw
            previousQualityRaw = ""
        } else if !previousLanguage.isEmpty {
            // Revert language change
            language = previousLanguage
            previousLanguage = ""
        }
    }
}

#Preview {
    SettingsView()
}
