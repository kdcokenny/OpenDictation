import XCTest
@testable import OpenDictation

@MainActor
final class ParakeetModelManagerTests: XCTestCase {
    private var tempDirectory: URL!
    private var sut: ParakeetModelManager!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParakeetModelManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let directory = tempDirectory!
        sut = ParakeetModelManager(cacheDirectory: { version in
            let folderName = switch version {
            case .v2: "parakeet-tdt-0.6b-v2-coreml"
            case .v3: "parakeet-tdt-0.6b-v3-coreml"
            }
            return directory.appendingPathComponent(folderName)
        })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        sut = nil
    }

    func testIncompleteCacheIsNotReady() {
        XCTAssertFalse(sut.isDownloaded(.v2))
        XCTAssertEqual(sut.readiness[.v2], .notDownloaded)
    }

    func testInstalledOnlyLoadRejectsIncompleteCacheWithoutDownloading() async {
        do {
            _ = try await sut.modelsIfInstalled(.v3)
            XCTFail("Expected missing model error")
        } catch let error as ParakeetError {
            guard case .modelNotDownloaded(.v3) = error else {
                return XCTFail("Expected v3 modelNotDownloaded, got \(error)")
            }
        } catch {
            XCTFail("Expected ParakeetError, got \(error)")
        }

        XCTAssertEqual(sut.readiness[.v3], .notDownloaded)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path),
            []
        )
    }
}
