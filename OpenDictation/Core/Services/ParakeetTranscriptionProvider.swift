import FluidAudio
import Foundation
import os.log

/// Offline Parakeet provider fixed to one model version for its full lifetime.
actor ParakeetTranscriptionProvider: TranscriptionProvider {
    private struct ManagerLoad: Sendable {
        let id: UUID
        let task: Task<AsrManager, Error>
    }

    static let english = ParakeetTranscriptionProvider(version: .v2)
    static let multilingual = ParakeetTranscriptionProvider(version: .v3)

    let version: ParakeetModelVersion

    private let logger = Logger.app(category: "ParakeetTranscriptionProvider")
    private let managerLoader: @Sendable (ParakeetModelVersion) async throws -> AsrManager
    private var asrManager: AsrManager?
    private var managerLoad: ManagerLoad?

    init(version: ParakeetModelVersion) {
        self.version = version
        managerLoader = Self.loadInstalledManager
    }

    init(
        version: ParakeetModelVersion,
        managerLoader: @escaping @Sendable (ParakeetModelVersion) async throws -> AsrManager
    ) {
        self.version = version
        self.managerLoader = managerLoader
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
        managerLoad?.task.cancel()
        managerLoad = nil
        asrManager = nil
        await ParakeetModelManager.shared.releasePreparedModels(for: version)
    }

    private func preparedManager() async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }

        if let managerLoad {
            return try await waitForManager(managerLoad)
        }

        let version = version
        let managerLoader = managerLoader
        let loadTask = Task<AsrManager, Error> {
            try await managerLoader(version)
        }
        let load = ManagerLoad(id: UUID(), task: loadTask)
        managerLoad = load
        return try await waitForManager(load)
    }

    private func waitForManager(_ load: ManagerLoad) async throws -> AsrManager {
        do {
            let manager = try await withTaskCancellationHandler {
                try await load.task.value
            } onCancel: {
                load.task.cancel()
            }
            guard !load.task.isCancelled else { throw CancellationError() }
            try Task.checkCancellation()

            if managerLoad?.id == load.id {
                managerLoad = nil
                asrManager = manager
            }
            return manager
        } catch {
            let wasCancelled = Task.isCancelled
                || load.task.isCancelled
                || error is CancellationError
            if managerLoad?.id == load.id {
                managerLoad = nil
            }
            if wasCancelled { throw CancellationError() }
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

    private static func loadInstalledManager(
        _ version: ParakeetModelVersion
    ) async throws -> AsrManager {
        let models = try await ParakeetModelManager.shared.modelsIfInstalled(version)
        try Task.checkCancellation()

        let fluidVersion = version.fluidAudioVersion
        let config = ASRConfig(
            tdtConfig: TdtConfig(blankId: fluidVersion.blankId),
            encoderHiddenSize: fluidVersion.encoderHiddenSize
        )
        let manager = AsrManager(config: config)
        try await manager.loadModels(models)
        try Task.checkCancellation()
        return manager
    }
}
