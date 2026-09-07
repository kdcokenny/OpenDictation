import Combine
import FluidAudio
import Foundation

enum ParakeetModelVersion: String, CaseIterable, Hashable, Sendable {
    case v2
    case v3

    var displayName: String {
        switch self {
        case .v2: return "Parakeet TDT v2 (English)"
        case .v3: return "Parakeet TDT v3 (25 languages)"
        }
    }

    var fluidAudioVersion: AsrModelVersion {
        switch self {
        case .v2: return .v2
        case .v3: return .v3
        }
    }
}

enum ParakeetModelReadiness: Equatable, Sendable {
    case notDownloaded
    case downloading
    case ready
    case failed(String)
}

enum ParakeetError: LocalizedError, Sendable {
    case modelNotDownloaded(ParakeetModelVersion)
    case modelOperationInProgress
    case unsupportedLanguage(String, ParakeetModelVersion)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let version):
            return "\(version.displayName) is not downloaded. Download it in Settings before using it."
        case .modelOperationInProgress:
            return "Another Parakeet model operation is still running."
        case .unsupportedLanguage(let language, let version):
            return "Language '\(language)' is not supported by \(version.displayName)."
        }
    }
}

/// Owns Parakeet downloads and loaded CoreML models.
/// Only `prepare(_:)` may download. All other loading paths require a complete local cache.
@MainActor
final class ParakeetModelManager: ObservableObject {
    private struct Preparation: Sendable {
        let id: UUID
        let task: Task<AsrModels, Error>
    }

    static let shared = ParakeetModelManager()

    @Published private(set) var downloadProgress: [ParakeetModelVersion: Double] = [:]
    @Published private(set) var readiness: [ParakeetModelVersion: ParakeetModelReadiness] = [:]
    @Published private(set) var lastError: [ParakeetModelVersion: String] = [:]

    private var preparedModels: [ParakeetModelVersion: AsrModels] = [:]
    private var preparations: [ParakeetModelVersion: Preparation] = [:]
    private let cacheDirectory: (ParakeetModelVersion) -> URL
    private var modelOperationInProgress = false

    init(
        cacheDirectory: @escaping (ParakeetModelVersion) -> URL = { version in
            AsrModels.defaultCacheDirectory(for: version.fluidAudioVersion)
        }
    ) {
        self.cacheDirectory = cacheDirectory
        refreshReadiness()
    }

    func isDownloaded(_ version: ParakeetModelVersion) -> Bool {
        let fluidVersion = version.fluidAudioVersion
        return AsrModels.modelsExist(at: cacheDirectory(version), version: fluidVersion)
    }

    /// Downloads and loads a model after an explicit user action.
    func prepare(_ version: ParakeetModelVersion) async throws {
        if preparedModels[version] != nil {
            readiness[version] = .ready
            return
        }

        if let preparation = preparations[version] {
            try await waitForPreparation(preparation, version: version)
            return
        }
        guard !modelOperationInProgress else {
            throw ParakeetError.modelOperationInProgress
        }

        modelOperationInProgress = true
        readiness[version] = .downloading
        downloadProgress[version] = 0
        lastError.removeValue(forKey: version)

        let preparationID = UUID()
        let directory = cacheDirectory(version)
        let fluidVersion = version.fluidAudioVersion
        let task = Task<AsrModels, Error> { [weak self] in
            try Task.checkCancellation()
            return try await AsrModels.downloadAndLoad(
                to: directory,
                version: fluidVersion,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.recordProgress(
                            progress.fractionCompleted,
                            for: version,
                            preparationID: preparationID
                        )
                    }
                }
            )
        }
        let preparation = Preparation(id: preparationID, task: task)
        preparations[version] = preparation
        try await waitForPreparation(preparation, version: version)
    }

    func cancelPreparation(_ version: ParakeetModelVersion) {
        preparations[version]?.task.cancel()
    }

    private func waitForPreparation(
        _ preparation: Preparation,
        version: ParakeetModelVersion
    ) async throws {
        do {
            let models = try await withTaskCancellationHandler {
                try await preparation.task.value
            } onCancel: {
                preparation.task.cancel()
            }
            guard !preparation.task.isCancelled else {
                throw CancellationError()
            }
            try Task.checkCancellation()

            guard isCurrent(preparation, for: version) else { return }
            preparedModels[version] = models
            downloadProgress[version] = 1
            readiness[version] = .ready
            preparations.removeValue(forKey: version)
            modelOperationInProgress = false
        } catch {
            let wasCancelled = Task.isCancelled
                || preparation.task.isCancelled
                || error is CancellationError
            guard isCurrent(preparation, for: version) else {
                if wasCancelled { throw CancellationError() }
                throw error
            }

            preparations.removeValue(forKey: version)
            modelOperationInProgress = false
            if wasCancelled {
                downloadProgress.removeValue(forKey: version)
                refreshReadiness(for: version)
                throw CancellationError()
            }
            let message = error.localizedDescription
            downloadProgress.removeValue(forKey: version)
            lastError[version] = message
            readiness[version] = .failed(message)
            throw error
        }
    }

    private func recordProgress(
        _ progress: Double,
        for version: ParakeetModelVersion,
        preparationID: UUID
    ) {
        guard preparations[version]?.id == preparationID,
              readiness[version] == .downloading else { return }
        downloadProgress[version] = progress
    }

    private func isCurrent(
        _ preparation: Preparation,
        for version: ParakeetModelVersion
    ) -> Bool {
        preparations[version]?.id == preparation.id
    }

    /// Loads an installed model to remove first-transcription latency.
    /// A missing or incomplete cache fails before FluidAudio is asked to load it.
    func prewarmIfInstalled(_ version: ParakeetModelVersion) async throws {
        _ = try await modelsIfInstalled(version)
    }

    func releasePreparedModels(for version: ParakeetModelVersion) {
        preparedModels.removeValue(forKey: version)
        guard preparations[version] == nil else { return }
        refreshReadiness(for: version)
    }

    func refreshReadiness() {
        for version in ParakeetModelVersion.allCases {
            refreshReadiness(for: version)
        }
    }

    func modelsIfInstalled(_ version: ParakeetModelVersion) async throws -> AsrModels {
        if let models = preparedModels[version] {
            return models
        }

        guard isDownloaded(version) else {
            readiness[version] = .notDownloaded
            throw ParakeetError.modelNotDownloaded(version)
        }
        guard !modelOperationInProgress else {
            throw ParakeetError.modelOperationInProgress
        }

        modelOperationInProgress = true
        defer { modelOperationInProgress = false }
        do {
            let fluidVersion = version.fluidAudioVersion
            let previousOfflineMode = ModelHub.offlineMode
            ModelHub.offlineMode = true
            defer { ModelHub.offlineMode = previousOfflineMode }
            let models = try await AsrModels.load(
                from: cacheDirectory(version),
                version: fluidVersion
            )
            preparedModels[version] = models
            readiness[version] = .ready
            lastError.removeValue(forKey: version)
            return models
        } catch {
            if Task.isCancelled {
                refreshReadiness(for: version)
                throw CancellationError()
            }
            let message = error.localizedDescription
            lastError[version] = message
            readiness[version] = .failed(message)
            throw error
        }
    }

    private func refreshReadiness(for version: ParakeetModelVersion) {
        guard preparations[version] == nil else {
            readiness[version] = .downloading
            return
        }
        if preparedModels[version] != nil || isDownloaded(version) {
            readiness[version] = .ready
            lastError.removeValue(forKey: version)
        } else {
            readiness[version] = .notDownloaded
        }
    }
}
