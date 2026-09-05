import Foundation
import os.log

/// Owns engine selection and the shared output pipeline for every dictation and retry.
actor TranscriptionCoordinator {
    static let shared = TranscriptionCoordinator()

    private let logger = Logger.app(category: "TranscriptionCoordinator")
    private var isTranscribing = false
    private var prewarmTask: Task<Void, Never>?
    private var needsPrewarm = false

    nonisolated var currentMode: TranscriptionMode {
        let value = UserDefaults.standard.string(forKey: "transcriptionMode") ?? TranscriptionMode.local.rawValue
        return TranscriptionMode(rawValue: value) ?? .local
    }

    nonisolated func setMode(_ mode: TranscriptionMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "transcriptionMode")
    }

    private func selectedLocalEngine() throws -> LocalSpeechEngine {
        let value = UserDefaults.standard.string(forKey: "localSpeechEngine") ?? LocalSpeechEngine.whisper.rawValue
        guard let engine = LocalSpeechEngine(rawValue: value) else {
            throw TranscriptionError.invalidConfiguration("Choose a supported speech engine in Settings.")
        }
        return engine
    }

    func transcribe(audioURL: URL, context: ContextProfile) async throws -> String {
        try Task.checkCancellation()
        guard !isTranscribing else {
            throw TranscriptionError.invalidConfiguration("Another transcription is finishing. Try again shortly.")
        }
        isTranscribing = true
        defer {
            isTranscribing = false
            if needsPrewarm {
                Task { await prewarmSelectedLocalModel() }
            }
        }

        let mode = currentMode
        let dictionary = try DictationDictionary.load()
        let engine = mode == .local ? try selectedLocalEngine() : nil
        let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
        if let engine, !engine.supportsLanguage(language) {
            throw TranscriptionError.invalidConfiguration("\(engine.displayName) doesn't support this language. Choose another engine or language in Settings.")
        }

        // A warm-up owns model loading/unloading until it finishes. Never unload a live engine.
        await prewarmTask?.value
        try Task.checkCancellation()
        await releaseInactiveEngines(keeping: engine)
        if engine == .whisper,
           !(await ModelManager.shared.currentModelSupportsLanguage(language)) {
            throw TranscriptionError.invalidConfiguration("Choose a Whisper model that supports your language in Settings.")
        }

        let text: String
        switch engine {
        case .whisper:
            text = try await LocalTranscriptionProvider.shared.transcribe(audioURL: audioURL, context: context)
        case .parakeetV2:
            text = try await ParakeetTranscriptionProvider.english.transcribe(audioURL: audioURL, context: context)
        case .parakeetV3:
            text = try await ParakeetTranscriptionProvider.multilingual.transcribe(audioURL: audioURL, context: context)
        case nil:
            text = try await CloudTranscriptionProvider.shared.transcribe(audioURL: audioURL, context: context)
        }
        try Task.checkCancellation()
        return dictionary.apply(to: TranscriptionOutputFilter.filter(text))
    }

    /// Warms installed models only. Downloads require an explicit Settings action.
    func prewarmSelectedLocalModel() async {
        guard !AppEnvironment.isRunningTests else { return }
        guard !isTranscribing, prewarmTask == nil else {
            needsPrewarm = true
            return
        }
        needsPrewarm = false
        let mode = currentMode
        let engine: LocalSpeechEngine?
        do {
            engine = mode == .local ? try selectedLocalEngine() : nil
        } catch {
            logger.error("Cannot prepare speech engine: \(error.localizedDescription)")
            return
        }

        let task = Task {
            do {
                await releaseInactiveEngines(keeping: engine)
                switch engine {
                case .whisper:
                    try await LocalTranscriptionProvider.shared.prewarmIfInstalled()
                case .parakeetV2:
                    try await ParakeetTranscriptionProvider.english.prewarmIfInstalled()
                case .parakeetV3:
                    try await ParakeetTranscriptionProvider.multilingual.prewarmIfInstalled()
                case nil:
                    break
                }
            } catch {
                // Settings owns visible readiness/error state; recording will report any load failure.
                logger.info("Speech engine is not ready: \(error.localizedDescription)")
            }
        }
        prewarmTask = task
        await task.value
        prewarmTask = nil
        if needsPrewarm { await prewarmSelectedLocalModel() }
    }

    private func releaseInactiveEngines(keeping engine: LocalSpeechEngine?) async {
        if engine != .whisper { await LocalTranscriptionProvider.shared.releaseContext() }
        if engine != .parakeetV2 { await ParakeetTranscriptionProvider.english.releaseModels() }
        if engine != .parakeetV3 { await ParakeetTranscriptionProvider.multilingual.releaseModels() }
    }

    func validateCurrentMode() async -> String? {
        do {
            _ = try DictationDictionary.load()
            switch currentMode {
            case .local:
                let engine = try selectedLocalEngine()
                let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
                guard engine.supportsLanguage(language) else {
                    return "Choose an engine that supports your language in Settings."
                }
                if let version = engine.parakeetVersion {
                    return await ParakeetModelManager.shared.isDownloaded(version)
                        ? nil : "Download \(engine.displayName) in Settings."
                }
                let manager = await ModelManager.shared
                guard await manager.currentModelSupportsLanguage(language) else {
                    return "Choose a Whisper model that supports your language in Settings."
                }
                return await manager.selectedModel == nil ? "Download and choose a Whisper model in Settings." : nil
            case .cloud:
                _ = try CloudTranscriptionConfiguration.load().endpoint()
                guard let key = KeychainService.shared.load(KeychainService.Key.apiKey),
                      !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return "Add your API key in Settings."
                }
                return nil
            }
        } catch {
            return error.localizedDescription
        }
    }
}
