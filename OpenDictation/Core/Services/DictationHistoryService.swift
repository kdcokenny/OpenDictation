import AppKit
import Combine
import Foundation
import os.log

/// A short-lived recovery record for one dictation attempt.
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
    var expiresAt: Date
    let audioURL: URL?
    let context: ContextProfile
    var transcriptionStatus: TranscriptionStatus
    var deliveryStatus: DeliveryStatus
    var lastTranscript: String?

    var transcript: String? {
        if case .succeeded(let text) = transcriptionStatus {
            return text
        }
        return lastTranscript
    }

    var isTranscribing: Bool {
        switch transcriptionStatus {
        case .pending, .retrying:
            return true
        case .succeeded, .empty, .failed:
            return false
        }
    }

    var canRetry: Bool {
        guard !isTranscribing else { return false }
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
    private let pasteboard: NSPasteboard
    private let writePasteboardString: (NSPasteboard, String) -> Bool
    private var pruneTask: Task<Void, Never>?

    private struct SavedPasteboardContents {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    init(
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil,
        maxEntries: Int = Defaults.maxEntries,
        timeToLive: TimeInterval = Defaults.timeToLive,
        now: @escaping () -> Date = Date.init,
        transcribe: ((URL, ContextProfile) async throws -> String)? = nil,
        pasteboard: NSPasteboard = .general,
        writePasteboardString: ((NSPasteboard, String) -> Bool)? = nil
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
        self.pasteboard = pasteboard
        self.writePasteboardString = writePasteboardString ?? {
            $0.setString($1, forType: .string)
        }

        ensureCacheDirectory()
        cleanupRetainedAudio()
    }

    deinit {
        pruneTask?.cancel()
    }

    /// Creates a history entry and claims the recorder temp file for retry.
    func createEntry(audioURL: URL, context: ContextProfile) -> UUID {
        pruneExpiredEntries()

        let id = UUID()
        let createdAt = now()
        let retainedAudioURL = claimAudio(from: audioURL, id: id)
        let entry = DictationHistoryEntry(
            id: id,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(timeToLive),
            audioURL: retainedAudioURL,
            context: context,
            transcriptionStatus: .pending,
            deliveryStatus: .notAttempted,
            lastTranscript: nil
        )

        entries.insert(entry, at: 0)
        pruneOverflowEntries()
        schedulePrune()
        return id
    }

    func markRetrying(id: UUID) {
        updateEntry(id: id) { entry in
            entry.expiresAt = now().addingTimeInterval(timeToLive)
            entry.transcriptionStatus = .retrying
            entry.deliveryStatus = .notAttempted
        }
    }

    func markTranscriptionSucceeded(id: UUID, text: String) {
        updateEntry(id: id) { entry in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.expiresAt = now().addingTimeInterval(timeToLive)
            if trimmed.isEmpty {
                entry.lastTranscript = nil
            } else {
                entry.lastTranscript = trimmed
            }
            entry.transcriptionStatus = trimmed.isEmpty ? .empty : .succeeded(trimmed)
        }
    }

    func markTranscriptionFailed(id: UUID, message: String) {
        updateEntry(id: id) { entry in
            entry.expiresAt = now().addingTimeInterval(timeToLive)
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

        guard let entry = entries.first(where: { $0.id == id }) else { return }
        guard !entry.isTranscribing else { return }

        guard let audioURL = entry.audioURL,
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

    @discardableResult
    func copyTranscript(id: UUID) -> Bool {
        pruneExpiredEntries()

        guard let text = entries.first(where: { $0.id == id })?.transcript,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let savedContents = savePasteboardContents(pasteboard)
        pasteboard.clearContents()
        guard writePasteboardString(pasteboard, text),
              pasteboard.string(forType: .string) == text else {
            restorePasteboardContents(savedContents, to: pasteboard)
            return false
        }

        return true
    }

    func discardEntry(id: UUID) {
        removeEntries { $0.id == id }
        schedulePrune()
    }

    func pruneExpiredEntries() {
        let currentDate = now()
        removeEntries { entry in
            !entry.isTranscribing && entry.expiresAt <= currentDate
        }
        schedulePrune()
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
        schedulePrune()
    }

    private func updateEntry(id: UUID, update: (inout DictationHistoryEntry) -> Void) {
        pruneExpiredEntries()

        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        update(&entries[index])
        schedulePrune()
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
        while entries.count > maxEntries {
            guard let index = entries.indices.reversed().first(where: { !entries[$0].isTranscribing }) else {
                return
            }

            let removed = entries.remove(at: index)
            deleteAudio(for: removed)
        }
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

    private func savePasteboardContents(_ pasteboard: NSPasteboard) -> SavedPasteboardContents {
        var items: [[NSPasteboard.PasteboardType: Data]] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            if !itemData.isEmpty {
                items.append(itemData)
            }
        }

        return SavedPasteboardContents(items: items)
    }

    private func restorePasteboardContents(
        _ saved: SavedPasteboardContents,
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()

        guard !saved.items.isEmpty else { return }

        let pasteboardItems = saved.items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        if !pasteboard.writeObjects(pasteboardItems) {
            logger.warning("Failed to restore clipboard after Recent copy failure.")
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

    private func schedulePrune() {
        pruneTask?.cancel()

        guard let nextExpiration = entries
            .filter({ !$0.isTranscribing })
            .map(\.expiresAt)
            .min() else {
            pruneTask = nil
            return
        }

        let delay = max(0, nextExpiration.timeIntervalSince(now()))
        pruneTask = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pruneExpiredEntries()
            }
        }
    }
}
