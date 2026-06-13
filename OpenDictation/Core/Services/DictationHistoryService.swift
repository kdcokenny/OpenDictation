import AppKit
import Foundation
import os.log

/// A short-lived recovery record for one completed dictation attempt.
struct DictationHistoryEntry: Identifiable, Equatable {
    enum TranscriptionStatus: Equatable {
        case pending
        case retrying
        case succeeded(String)
        case empty
        case failed(String)
    }

    enum DeliveryStatus: Equatable {
        case notAttempted
        case inserted
        case copiedOnly
        case failed(String)
    }

    let id: UUID
    let createdAt: Date
    let audioURL: URL?
    let context: ContextProfile
    var transcriptionStatus: TranscriptionStatus
    var deliveryStatus: DeliveryStatus

    var transcript: String? {
        guard case .succeeded(let text) = transcriptionStatus else { return nil }
        return text
    }

    var canRetry: Bool {
        guard let audioURL else { return false }
        return FileManager.default.fileExists(atPath: audioURL.path)
    }
}

/// Session-only owner for recent dictation recovery entries and retained audio files.
@MainActor
final class DictationHistoryService: ObservableObject {

    static let shared = DictationHistoryService()

    private enum Defaults {
        static let maxEntries = 10
        static let timeToLive: TimeInterval = 30 * 60
    }

    @Published private(set) var entries: [DictationHistoryEntry] = []

    private let logger = Logger.app(category: "DictationHistoryService")
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let maxEntries: Int
    private let timeToLive: TimeInterval
    private let now: () -> Date
    private let transcribe: (URL, ContextProfile) async throws -> String

    init(
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil,
        maxEntries: Int = Defaults.maxEntries,
        timeToLive: TimeInterval = Defaults.timeToLive,
        now: @escaping () -> Date = Date.init,
        transcribe: ((URL, ContextProfile) async throws -> String)? = nil
    ) {
        self.fileManager = fileManager
        self.cacheDirectory = cacheDirectory ?? fileManager
            .temporaryDirectory
            .appendingPathComponent("OpenDictationRecent", isDirectory: true)
        self.maxEntries = maxEntries
        self.timeToLive = timeToLive
        self.now = now
        self.transcribe = transcribe ?? {
            try await TranscriptionCoordinator.shared.transcribe(audioURL: $0, context: $1)
        }

        ensureCacheDirectory()
        cleanupRetainedAudio()
    }

    /// Creates a history entry and claims the recorder temp file for retry.
    func createEntry(audioURL: URL, context: ContextProfile) -> UUID {
        pruneExpiredEntries()

        let id = UUID()
        let retainedAudioURL = claimAudio(from: audioURL, id: id)
        let entry = DictationHistoryEntry(
            id: id,
            createdAt: now(),
            audioURL: retainedAudioURL,
            context: context,
            transcriptionStatus: .pending,
            deliveryStatus: .notAttempted
        )

        entries.insert(entry, at: 0)
        pruneOverflowEntries()
        return id
    }

    func markRetrying(id: UUID) {
        updateEntry(id: id) { entry in
            entry.transcriptionStatus = .retrying
            entry.deliveryStatus = .notAttempted
        }
    }

    func markTranscriptionSucceeded(id: UUID, text: String) {
        updateEntry(id: id) { entry in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.transcriptionStatus = trimmed.isEmpty ? .empty : .succeeded(trimmed)
        }
    }

    func markTranscriptionFailed(id: UUID, message: String) {
        updateEntry(id: id) { entry in
            entry.transcriptionStatus = .failed(message)
            entry.deliveryStatus = .notAttempted
        }
    }

    func markDelivery(id: UUID, result: TextDeliveryResult) {
        updateEntry(id: id) { entry in
            switch result {
            case .inserted:
                entry.deliveryStatus = .inserted
            case .copiedOnly:
                entry.deliveryStatus = .copiedOnly
            case .failed(let message):
                entry.deliveryStatus = .failed(message)
            }
        }
    }

    func retryTranscription(id: UUID) async {
        pruneExpiredEntries()

        guard let entry = entries.first(where: { $0.id == id }),
              let audioURL = entry.audioURL,
              fileManager.fileExists(atPath: audioURL.path) else {
            markTranscriptionFailed(id: id, message: "Audio is no longer available.")
            return
        }

        markRetrying(id: id)

        do {
            let text = try await transcribe(audioURL, entry.context)
            markTranscriptionSucceeded(id: id, text: text)
        } catch {
            markTranscriptionFailed(id: id, message: error.localizedDescription)
        }
    }

    func copyTranscript(id: UUID) {
        guard let text = entries.first(where: { $0.id == id })?.transcript,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pruneExpiredEntries() {
        let cutoff = now().addingTimeInterval(-timeToLive)
        removeEntries { $0.createdAt < cutoff }
    }

    func cleanupRetainedAudio() {
        for entry in entries {
            deleteAudio(for: entry)
        }
        entries.removeAll()

        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
            }
            ensureCacheDirectory()
        } catch {
            logger.warning("Failed to clean recent audio cache: \(error.localizedDescription)")
        }
    }

    private func updateEntry(id: UUID, update: (inout DictationHistoryEntry) -> Void) {
        pruneExpiredEntries()

        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        update(&entries[index])
    }

    private func claimAudio(from sourceURL: URL, id: UUID) -> URL? {
        ensureCacheDirectory()

        let destinationURL = cacheDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            logger.warning("Failed to claim audio for Recent: \(error.localizedDescription)")
            return nil
        }
    }

    private func pruneOverflowEntries() {
        guard entries.count > maxEntries else { return }
        let overflow = entries.suffix(entries.count - maxEntries)
        overflow.forEach(deleteAudio)
        entries.removeLast(entries.count - maxEntries)
    }

    private func removeEntries(where shouldRemove: (DictationHistoryEntry) -> Bool) {
        let removed = entries.filter(shouldRemove)
        removed.forEach(deleteAudio)
        entries.removeAll(where: shouldRemove)
    }

    private func deleteAudio(for entry: DictationHistoryEntry) {
        guard let audioURL = entry.audioURL,
              fileManager.fileExists(atPath: audioURL.path) else { return }

        do {
            try fileManager.removeItem(at: audioURL)
        } catch {
            logger.warning("Failed to delete recent audio: \(error.localizedDescription)")
        }
    }

    private func ensureCacheDirectory() {
        guard !fileManager.fileExists(atPath: cacheDirectory.path) else { return }

        do {
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning("Failed to create recent audio cache: \(error.localizedDescription)")
        }
    }
}
