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
    case preparationInProgress(ParakeetModelVersion)
    case modelOperationInProgress
    case unsupportedLanguage(String, ParakeetModelVersion)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let version):
            return "\(version.displayName) is not downloaded. Download it in Settings before using it."
        case .preparationInProgress(let version):
            return "\(version.displayName) is already being prepared."
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
    static let shared = ParakeetModelManager()

    @Published private(set) var downloadProgress: [ParakeetModelVersion: Double] = [:]
    @Published private(set) var readiness: [ParakeetModelVersion: ParakeetModelReadiness] = [:]
    @Published private(set) var lastError: [ParakeetModelVersion: String] = [:]

    private var preparedModels: [ParakeetModelVersion: AsrModels] = [:]
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

        guard readiness[version] != .downloading else {
            throw ParakeetError.preparationInProgress(version)
        }
        guard !modelOperationInProgress else {
            throw ParakeetError.modelOperationInProgress
        }

        modelOperationInProgress = true
        defer { modelOperationInProgress = false }
        readiness[version] = .downloading
        downloadProgress[version] = 0
        lastError.removeValue(forKey: version)

        do {
            try Task.checkCancellation()
            let fluidVersion = version.fluidAudioVersion
            let models = try await AsrModels.downloadAndLoad(
                to: cacheDirectory(version),
                version: fluidVersion,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.readiness[version] == .downloading else {
                            return
                        }
                        self.downloadProgress[version] = progress.fractionCompleted
                    }
                }
            )
            try Task.checkCancellation()
            preparedModels[version] = models
            downloadProgress[version] = 1
            readiness[version] = .ready
        } catch {
            if Task.isCancelled {
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

    /// Loads an installed model to remove first-transcription latency.
    /// A missing or incomplete cache fails before FluidAudio is asked to load it.
    func prewarmIfInstalled(_ version: ParakeetModelVersion) async throws {
        _ = try await modelsIfInstalled(version)
    }

    func releasePreparedModels(for version: ParakeetModelVersion) {
        preparedModels.removeValue(forKey: version)
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
        if preparedModels[version] != nil || isDownloaded(version) {
            readiness[version] = .ready
            lastError.removeValue(forKey: version)
        } else {
            readiness[version] = .notDownloaded
        }
    }
}
