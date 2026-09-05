import Foundation
import XCTest
@testable import OpenDictation

final class ParakeetTranscriptionProviderTests: XCTestCase {
    func testCancellingPrewarmCancelsSharedModelLoad() async {
        let cancellation = CancellationProbe()
        let provider = ParakeetTranscriptionProvider(version: .v2) { _ in
            try await withTaskCancellationHandler {
                try await Task.sleep(for: .seconds(1))
                throw TestLoaderError.finishedWithoutCancellation
            } onCancel: {
                cancellation.record()
            }
        }

        let prewarm = Task {
            try await provider.prewarmIfInstalled()
        }
        await Task.yield()
        prewarm.cancel()

        do {
            try await prewarm.value
            XCTFail("Expected prewarm to be cancelled")
        } catch is CancellationError {
            XCTAssertTrue(cancellation.wasRecorded)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}

private enum TestLoaderError: Error {
    case finishedWithoutCancellation
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = false

    var wasRecorded: Bool {
        lock.withLock { recorded }
    }

    func record() {
        lock.withLock { recorded = true }
    }
}
