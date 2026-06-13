import XCTest
import AppKit
@testable import OpenDictation

@MainActor
final class DictationHistoryServiceTests: XCTestCase {

    private var tempDirectory: URL!
    private var now: Date!
    private var pasteboardSnapshot: [[NSPasteboard.PasteboardType: Data]] = []

    override func setUp() async throws {
        try await super.setUp()
        pasteboardSnapshot = savePasteboardContents(NSPasteboard.general)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictationHistoryServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        now = Date(timeIntervalSince1970: 1_000)
    }

    override func tearDown() async throws {
        if let tempDirectory,
           FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        now = nil
        restorePasteboardContents(pasteboardSnapshot, to: NSPasteboard.general)
        pasteboardSnapshot = []
        try await super.tearDown()
    }

    func testCreateEntryClaimsAudio() throws {
        // Given
        let sourceURL = try makeAudioFile()
        let sut = makeService()

        // When
        let id = sut.createEntry(audioURL: sourceURL, context: .code)

        // Then
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries.first?.id, id)
        XCTAssertEqual(sut.entries.first?.context, .code)
        XCTAssertNotEqual(sut.entries.first?.audioURL, sourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.entries.first?.audioURL?.path ?? ""))
    }

    func testMaxCountPrunesOldestEntryAndDeletesAudio() throws {
        // Given
        let sut = makeService(maxEntries: 1)
        let firstID = sut.createEntry(audioURL: try makeAudioFile(name: "first.wav"), context: .prose)
        let firstAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == firstID })?.audioURL)
        sut.markTranscriptionSucceeded(id: firstID, text: "First transcript")

        // When
        let secondID = sut.createEntry(audioURL: try makeAudioFile(name: "second.wav"), context: .code)

        // Then
        XCTAssertEqual(sut.entries.map(\.id), [secondID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstAudioURL.path))
    }

    func testMaxCountSkipsTranscribingEntryWhenPruningOverflow() throws {
        // Given
        let sut = makeService(maxEntries: 2)
        let retryingID = sut.createEntry(audioURL: try makeAudioFile(name: "retrying.wav"), context: .prose)
        let retryingAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == retryingID })?.audioURL)
        sut.markTranscriptionFailed(id: retryingID, message: "Previous failure")
        sut.markRetrying(id: retryingID)

        let terminalID = sut.createEntry(audioURL: try makeAudioFile(name: "terminal.wav"), context: .code)
        let terminalAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == terminalID })?.audioURL)
        sut.markTranscriptionSucceeded(id: terminalID, text: "Terminal transcript")

        // When
        let pendingID = sut.createEntry(audioURL: try makeAudioFile(name: "pending.wav"), context: .prose)

        // Then
        XCTAssertEqual(sut.entries.map(\.id), [pendingID, retryingID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: retryingAudioURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: terminalAudioURL.path))
    }

    func testTTLPrunesExpiredTerminalEntryAndDeletesAudio() throws {
        // Given
        let sut = makeService(timeToLive: 60)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == id })?.audioURL)
        sut.markTranscriptionSucceeded(id: id, text: "Finished transcript")

        // When
        now = now.addingTimeInterval(61)
        sut.pruneExpiredEntries()

        // Then
        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedAudioURL.path))
    }

    func testTTLPrunesTerminalEntryWhileServiceIsIdle() async throws {
        // Given
        let sut = makeLiveService(timeToLive: 0.05)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == id })?.audioURL)
        sut.markTranscriptionSucceeded(id: id, text: "Finished transcript")

        // When
        try await Task.sleep(nanoseconds: 150_000_000)

        // Then
        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedAudioURL.path))
    }

    func testPendingEntryIsNotPrunedWhileTranscriptionIsRunning() throws {
        // Given
        let sut = makeService(timeToLive: 60)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == id })?.audioURL)

        // When
        now = now.addingTimeInterval(61)
        sut.pruneExpiredEntries()

        // Then
        XCTAssertEqual(sut.entries.first?.id, id)
        XCTAssertEqual(sut.entries.first?.transcriptionStatus, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedAudioURL.path))
    }

    func testRetryFailureUpdatesEntry() async throws {
        // Given
        let sut = makeService(timeToLive: 60)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first?.audioURL)
        sut.markTranscriptionFailed(id: id, message: "Previous failure")
        try FileManager.default.removeItem(at: retainedAudioURL)

        // When
        await sut.retryTranscription(id: id)

        // Then
        guard case .failed("Audio is no longer available.") = sut.entries.first?.transcriptionStatus else {
            return XCTFail("Expected missing audio retry failure")
        }
    }

    func testRetryUpdatesFailedEntryToSucceeded() async throws {
        // Given
        let sut = makeService { _, context in
            XCTAssertEqual(context, .code)
            return " Regenerated transcript "
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .code)
        sut.markTranscriptionFailed(id: id, message: "Network failed")

        // When
        await sut.retryTranscription(id: id)

        // Then
        XCTAssertEqual(sut.entries.first?.transcriptionStatus, .succeeded("Regenerated transcript"))
        XCTAssertEqual(sut.entries.first?.deliveryStatus, .notAttempted)
    }

    func testRetryFailurePreservesLastTranscript() async throws {
        // Given
        let sut = makeService { _, _ in
            throw NSError(domain: "DictationHistoryServiceTests", code: 2)
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        sut.markTranscriptionSucceeded(id: id, text: " Original transcript ")

        // When
        await sut.retryTranscription(id: id)

        // Then
        guard case .failed(let message) = sut.entries.first?.transcriptionStatus else {
            return XCTFail("Expected retry failure")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(sut.entries.first?.transcript, "Original transcript")
        XCTAssertEqual(sut.entries.first?.deliveryStatus, .notAttempted)
    }

    func testEmptyRetryClearsLastTranscript() async throws {
        // Given
        let sut = makeService { _, _ in
            " "
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        sut.markTranscriptionSucceeded(id: id, text: "Old transcript")

        // When
        await sut.retryTranscription(id: id)

        // Then
        XCTAssertEqual(sut.entries.first?.transcriptionStatus, .empty)
        XCTAssertNil(sut.entries.first?.transcript)
    }

    func testRetryingEntryIsNotPrunedWhileTranscriptionIsRunning() async throws {
        // Given
        let sut = makeService(timeToLive: 60) { _, _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            return "Regenerated transcript"
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        sut.markTranscriptionFailed(id: id, message: "Previous failure")
        now = now.addingTimeInterval(59)

        // When
        let retryTask = Task {
            await sut.retryTranscription(id: id)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        now = now.addingTimeInterval(61)
        sut.pruneExpiredEntries()

        // Then
        XCTAssertEqual(sut.entries.first?.transcriptionStatus, .retrying)
        await retryTask.value
        XCTAssertEqual(sut.entries.first?.transcriptionStatus, .succeeded("Regenerated transcript"))
    }

    func testPendingEntryCannotStartSecondRetry() async throws {
        // Given
        var retryCount = 0
        let sut = makeService { _, _ in
            retryCount += 1
            return "Unexpected"
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)

        // When
        await sut.retryTranscription(id: id)

        // Then
        XCTAssertEqual(retryCount, 0)
        XCTAssertEqual(sut.entries.first?.transcriptionStatus, .pending)
    }

    func testRetryUpdatesEmptyEntryToFailed() async throws {
        // Given
        let sut = makeService { _, _ in
            throw NSError(domain: "DictationHistoryServiceTests", code: 1)
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        sut.markTranscriptionSucceeded(id: id, text: " ")

        // When
        await sut.retryTranscription(id: id)

        // Then
        guard case .failed(let message) = sut.entries.first?.transcriptionStatus else {
            return XCTFail("Expected retry failure")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(sut.entries.first?.deliveryStatus, .notAttempted)
    }

    func testDeliveryStatusUpdatesFromResult() throws {
        // Given
        let sut = makeService()
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)

        // When
        sut.markDelivery(id: id, result: .copiedOnly)

        // Then
        XCTAssertEqual(sut.entries.first?.deliveryStatus, .copiedOnly)
    }

    func testCopyTranscriptPrunesExpiredEntryAndDeletesAudio() throws {
        // Given
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Existing clipboard", forType: .string)

        let sut = makeService(timeToLive: 60)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first?.audioURL)
        sut.markTranscriptionSucceeded(id: id, text: "Copy me")

        // When
        now = now.addingTimeInterval(61)
        let didCopy = sut.copyTranscript(id: id)

        // Then
        XCTAssertFalse(didCopy)
        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedAudioURL.path))
        XCTAssertEqual(pasteboard.string(forType: .string), "Existing clipboard")
    }

    func testCopyTranscriptRestoresClipboardWhenPasteboardWriteFails() throws {
        // Given
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Existing clipboard", forType: .string)

        let sut = makeService { pasteboard, _ in
            pasteboard.clearContents()
            return false
        }
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        sut.markTranscriptionSucceeded(id: id, text: "Copy me")

        // When
        let didCopy = sut.copyTranscript(id: id)

        // Then
        XCTAssertFalse(didCopy)
        XCTAssertEqual(pasteboard.string(forType: .string), "Existing clipboard")
    }

    func testDiscardEntryDeletesAudio() throws {
        // Given
        let sut = makeService()
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first?.audioURL)

        // When
        sut.discardEntry(id: id)

        // Then
        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedAudioURL.path))
    }

    private func makeService(
        maxEntries: Int = 10,
        timeToLive: TimeInterval = 30 * 60,
        transcribe: @escaping (URL, ContextProfile) async throws -> String = { _, _ in "" }
    ) -> DictationHistoryService {
        DictationHistoryService(
            cacheDirectory: tempDirectory.appendingPathComponent("cache", isDirectory: true),
            maxEntries: maxEntries,
            timeToLive: timeToLive,
            now: { self.now },
            transcribe: transcribe
        )
    }

    private func makeService(
        writePasteboardString: @escaping (NSPasteboard, String) -> Bool
    ) -> DictationHistoryService {
        DictationHistoryService(
            cacheDirectory: tempDirectory.appendingPathComponent("cache", isDirectory: true),
            now: { self.now },
            transcribe: { _, _ in "" },
            writePasteboardString: writePasteboardString
        )
    }

    private func makeLiveService(timeToLive: TimeInterval) -> DictationHistoryService {
        DictationHistoryService(
            cacheDirectory: tempDirectory.appendingPathComponent("live-cache", isDirectory: true),
            timeToLive: timeToLive
        )
    }

    private func makeAudioFile(name: String = "audio.wav") throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }

    private func savePasteboardContents(
        _ pasteboard: NSPasteboard
    ) -> [[NSPasteboard.PasteboardType: Data]] {
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

        return items
    }

    private func restorePasteboardContents(
        _ savedItems: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()

        guard !savedItems.isEmpty else { return }

        let pasteboardItems = savedItems.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        XCTAssertTrue(
            pasteboard.writeObjects(pasteboardItems),
            "Failed to restore pasteboard contents"
        )
    }
}
