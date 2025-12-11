import SwiftUI
import KeyboardShortcuts

/// Main settings view for Open Dictate.
/// Provides configuration for shortcut, API key, and advanced transcription options.
struct SettingsView: View {
  
  // MARK: - State
  
  /// API key stored in Keychain (not @AppStorage for security)
  @State private var apiKey: String = ""
  @State private var isApiKeyVisible: Bool = false
  
  /// Advanced settings stored in UserDefaults
  @AppStorage("baseURL") private var baseURL: String = "https://api.openai.com/v1"
  @AppStorage("model") private var model: String = "whisper-1"
  @AppStorage("language") private var languageCode: String = ""
  @AppStorage("temperature") private var temperature: Double = 0.0
  
  /// Controls Advanced section expansion
  @State private var isAdvancedExpanded: Bool = false
  
  // MARK: - Body
  
  var body: some View {
    Form {
      // MARK: Shortcut Section
      Section {
        KeyboardShortcuts.Recorder("Shortcut:", name: .toggleDictation)
      }
      
      // MARK: API Configuration Section
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
          
          Text("Your OpenAI API key")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      } header: {
        Text("API Configuration")
          .font(.headline)
      }
      
      // MARK: Advanced Section
      Section {
        DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
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
              TextField("Model", text: $model)
                .textFieldStyle(.roundedBorder)
              Text("Default: whisper-1. Groq: whisper-large-v3-turbo")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            // Language Picker
            VStack(alignment: .leading, spacing: 4) {
              Picker("Language", selection: $languageCode) {
                ForEach(WhisperLanguage.all) { language in
                  Text(language.name).tag(language.code)
                }
              }
              Text("Select transcription language")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            // Temperature Slider
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("Temperature")
                Spacer()
                Text(String(format: "%.1f", temperature))
                  .foregroundColor(.secondary)
                  .frame(width: 30)
              }
              Slider(value: $temperature, in: 0...1, step: 0.1)
              Text("0 = deterministic, 1 = more variation")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          .padding(.top, 8)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 380)
    .onAppear {
      loadApiKey()
    }
    .onChange(of: apiKey) { _, newValue in
      saveApiKey(newValue)
    }
  }
  
  // MARK: - Keychain Helpers
  
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

#Preview {
  SettingsView()
}
