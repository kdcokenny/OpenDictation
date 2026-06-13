import XCTest
@testable import OpenDictation

@MainActor
final class DictationHistoryServiceTests: XCTestCase {

    private var tempDirectory: URL!
    private var now: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictationHistoryServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        now = Date(timeIntervalSince1970: 1_000)
    }

    override func tearDownWithError() throws {
        if let tempDirectory,
           FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        now = nil
        try super.tearDownWithError()
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

        // When
        let secondID = sut.createEntry(audioURL: try makeAudioFile(name: "second.wav"), context: .code)

        // Then
        XCTAssertEqual(sut.entries.map(\.id), [secondID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstAudioURL.path))
    }

    func testTTLPrunesExpiredEntryAndDeletesAudio() throws {
        // Given
        let sut = makeService(timeToLive: 60)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first(where: { $0.id == id })?.audioURL)

        // When
        now = now.addingTimeInterval(61)
        sut.pruneExpiredEntries()

        // Then
        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedAudioURL.path))
    }

    func testRetryFailureUpdatesEntry() async throws {
        // Given
        let sut = makeService(timeToLive: 60)
        let id = sut.createEntry(audioURL: try makeAudioFile(), context: .prose)
        let retainedAudioURL = try XCTUnwrap(sut.entries.first?.audioURL)
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

    private func makeAudioFile(name: String = "audio.wav") throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }
}
