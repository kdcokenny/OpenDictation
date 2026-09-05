import Foundation

struct CloudTranscriptionConfiguration: Sendable {
    var baseURL: String
    var model: String
    var language: String
    var temperature: Double

    static func load() -> Self {
        let defaults = UserDefaults.standard
        return Self(
            baseURL: defaults.string(forKey: "baseURL") ?? "https://api.openai.com/v1",
            model: defaults.string(forKey: "model") ?? "whisper-1",
            language: defaults.string(forKey: "language") ?? "auto",
            temperature: defaults.double(forKey: "temperature")
        )
    }

    var modelName: String {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "whisper-1" : name
    }

    var languageHint: String? {
        let code = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty || code == "auto" ? nil : code
    }

    var usesLanguageArray: Bool {
        modelName == "gpt-transcribe" || modelName.hasPrefix("gpt-transcribe-")
    }

    func endpoint() throws -> URL {
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = address.isEmpty ? "https://api.openai.com/v1" : address
        guard var components = URLComponents(string: resolved),
              let scheme = components.scheme, ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil else {
            throw TranscriptionError.invalidURL
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path != "audio/transcriptions" && !path.hasSuffix("/audio/transcriptions") {
            components.path = path.isEmpty ? "/audio/transcriptions" : "/\(path)/audio/transcriptions"
        } else {
            components.path = "/\(path)"
        }
        guard let url = components.url else { throw TranscriptionError.invalidURL }
        return url
    }
}

enum CloudTranscriptionPreset: String, CaseIterable, Identifiable {
    case openAITranscribe
    case openAIMini
    case openAIWhisper
    case groqTurbo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .openAITranscribe: return "OpenAI · GPT-Transcribe"
        case .openAIMini: return "OpenAI · GPT-4o mini transcribe"
        case .openAIWhisper: return "OpenAI · Whisper"
        case .groqTurbo: return "Groq · Whisper Turbo"
        }
    }

    var baseURL: String {
        self == .groqTurbo ? "https://api.groq.com/openai/v1" : "https://api.openai.com/v1"
    }

    var model: String {
        switch self {
        case .openAITranscribe: return "gpt-transcribe"
        case .openAIMini: return "gpt-4o-mini-transcribe"
        case .openAIWhisper: return "whisper-1"
        case .groqTurbo: return "whisper-large-v3-turbo"
        }
    }
}
