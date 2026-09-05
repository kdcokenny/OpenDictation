import FluidAudio
import Foundation
import os.log

/// Offline Parakeet provider fixed to one model version for its full lifetime.
actor ParakeetTranscriptionProvider: TranscriptionProvider {
    static let english = ParakeetTranscriptionProvider(version: .v2)
    static let multilingual = ParakeetTranscriptionProvider(version: .v3)

    let version: ParakeetModelVersion

    private let logger = Logger.app(category: "ParakeetTranscriptionProvider")
    private var asrManager: AsrManager?
    private var managerLoadTask: Task<AsrManager, Error>?

    init(version: ParakeetModelVersion) {
        self.version = version
    }

    func transcribe(audioURL: URL, context: ContextProfile) async throws -> String {
        _ = context
        try Task.checkCancellation()

        let language = try languageHint()
        let manager = try await preparedManager()
        try Task.checkCancellation()

        var decoderState = try TdtDecoderState(
            decoderLayers: version.fluidAudioVersion.decoderLayers
        )
        let result = try await manager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: language
        )
        try Task.checkCancellation()

        logger.info("Parakeet \(self.version.rawValue) transcription completed")
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prewarmIfInstalled() async throws {
        _ = try await preparedManager()
    }

    func releaseModels() async {
        managerLoadTask?.cancel()
        managerLoadTask = nil
        asrManager = nil
        await ParakeetModelManager.shared.releasePreparedModels(for: version)
    }

    private func preparedManager() async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }

        if let managerLoadTask {
            return try await managerLoadTask.value
        }

        let version = version
        let loadTask = Task {
            let models = try await ParakeetModelManager.shared.modelsIfInstalled(version)
            try Task.checkCancellation()

            let fluidVersion = version.fluidAudioVersion
            let config = ASRConfig(
                tdtConfig: TdtConfig(blankId: fluidVersion.blankId),
                encoderHiddenSize: fluidVersion.encoderHiddenSize
            )
            let manager = AsrManager(config: config)
            try await manager.loadModels(models)
            return manager
        }
        managerLoadTask = loadTask

        do {
            let manager = try await loadTask.value
            managerLoadTask = nil
            asrManager = manager
            return manager
        } catch {
            managerLoadTask = nil
            throw error
        }
    }

    private func languageHint() throws -> Language? {
        let languageCode = UserDefaults.standard.string(forKey: "language") ?? "auto"
        guard !languageCode.isEmpty, languageCode != "auto" else { return nil }

        switch version {
        case .v2:
            guard languageCode == "en" else {
                throw ParakeetError.unsupportedLanguage(languageCode, version)
            }
            return nil

        case .v3:
            guard LocalSpeechEngine.parakeetLanguages.contains(languageCode),
                  let language = Language(rawValue: languageCode) else {
                throw ParakeetError.unsupportedLanguage(languageCode, version)
            }
            return language
        }
    }
}
