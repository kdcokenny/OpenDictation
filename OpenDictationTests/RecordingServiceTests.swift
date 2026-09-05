import XCTest
@testable import OpenDictation

final class RecordingServiceTests: XCTestCase {
    @MainActor
    func testDeleteRecordingAtRemovesTheSuppliedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-service-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0, 1, 2]).write(to: url)

        RecordingService.shared.deleteRecording(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
