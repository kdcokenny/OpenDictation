@testable import OpenDictation
import XCTest

@MainActor
final class ModelManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var sut: ModelManager!
    private var previousSelectedModel: String?

    private let validModelContents = Data("valid model".utf8)

    private var bundledModel: WhisperModel {
        WhisperModel(
            id: UUID(),
            name: "test-whisper",
            displayName: "Test Whisper",
            size: "11 bytes",
            downloadURL: "https://example.com/test-whisper.bin",
            expectedByteCount: 11,
            sha256: "fe8d07f0cc8f22537e1bad3404430bec54ad778abbe9a7f15eec0e2b932e5a58",
            isMultilingual: true,
            description: "Test model",
            isBundled: true
        )
    }
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a unique temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        previousSelectedModel = UserDefaults.standard.string(forKey: "selectedLocalModel")
        UserDefaults.standard.set(bundledModel.name, forKey: "selectedLocalModel")
        sut = ModelManager(modelsDirectory: tempDirectory, models: [bundledModel])
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        if let previousSelectedModel {
            UserDefaults.standard.set(previousSelectedModel, forKey: "selectedLocalModel")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedLocalModel")
        }
        try await super.tearDown()
    }
    
    func testInitializationCreatesDirectory() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    func testInitialScanDoesNotPublishInvalidModel() async throws {
        let invalidModel = tempDirectory.appendingPathComponent(bundledModel.filename)
        try Data("short".utf8).write(to: invalidModel)

        let manager = ModelManager(modelsDirectory: tempDirectory, models: [bundledModel])
        await manager.waitForInitialScan()

        XCTAssertTrue(manager.downloadedModels.isEmpty)
        XCTAssertNotNil(manager.downloadErrors[bundledModel.name])
    }
    
    func testLoadDownloadedModels() async throws {
        // Given: Create a dummy model file
        let modelFile = tempDirectory.appendingPathComponent(bundledModel.filename)
        try validModelContents.write(to: modelFile)
        
        // When
        await sut.loadDownloadedModels()
        
        // Then
        XCTAssertEqual(sut.downloadedModels.count, 1)
        XCTAssertEqual(sut.downloadedModels.first?.name, bundledModel.name)
    }
    
    func testIsDownloaded() async throws {
        let model = bundledModel
        XCTAssertFalse(sut.isDownloaded(model))
        
        let path = tempDirectory.appendingPathComponent(model.filename)
        try validModelContents.write(to: path)
        
        await sut.loadDownloadedModels()
        XCTAssertTrue(sut.isDownloaded(model))
    }
    
    func testValidateSelectedModelFallsBackToBundled() async throws {
        // Given: We have a bundled model file on disk
        let bundled = bundledModel
        let bundledPath = tempDirectory.appendingPathComponent(bundled.filename)
        try validModelContents.write(to: bundledPath)
        await sut.loadDownloadedModels()
        
        // Set selected model to something non-existent
        sut.selectedModelName = "non-existent-model"
        XCTAssertEqual(sut.selectedModelName, "non-existent-model")
        
        // When
        sut.validateSelectedModelExists()
        
        // Then
        XCTAssertEqual(sut.selectedModelName, bundled.name, "Should fall back to bundled model if selected is missing")
    }
    
    func testRecommendedModelName() {
        // This is a logic test for the recommendation engine
        let name = sut.recommendedModelName
        XCTAssertFalse(name.isEmpty)
        // By default on most Macs it should be ggml-base or ggml-tiny
        XCTAssertTrue(name.contains("ggml-"))
    }

    func testLegacyEmptyLanguageUsesAutoDetection() {
        XCTAssertTrue(bundledModel.supportsLanguage(""))
    }

    func testUnknownSelectedModelFailsLanguageValidation() {
        sut.selectedModelName = "unknown-model"

        XCTAssertFalse(sut.currentModelSupportsLanguage("en"))
    }

    func testLoadDownloadedModelsRejectsWrongSize() async throws {
        let path = tempDirectory.appendingPathComponent(bundledModel.filename)
        try Data("short".utf8).write(to: path)

        await sut.loadDownloadedModels()

        XCTAssertTrue(sut.downloadedModels.isEmpty)
        XCTAssertNotNil(sut.downloadErrors[bundledModel.name])
    }

    func testInitializationRemovesOrphanedPartialFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerOrphanTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let orphan = directory.appendingPathComponent(".model.crashed.partial")
        try Data("incomplete".utf8).write(to: orphan)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -(25 * 60 * 60))],
            ofItemAtPath: orphan.path
        )

        let manager = ModelManager(modelsDirectory: directory, models: [bundledModel])

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        withExtendedLifetime(manager) {}
    }

    func testInitializationPreservesRecentPartialFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerActivePartialTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recentPartial = directory.appendingPathComponent(".model.active.partial")
        try Data("in progress".utf8).write(to: recentPartial)

        let manager = ModelManager(modelsDirectory: directory, models: [bundledModel])

        XCTAssertTrue(FileManager.default.fileExists(atPath: recentPartial.path))
        withExtendedLifetime(manager) {}
    }

    func testValidatorRejectsWrongChecksum() throws {
        let path = tempDirectory.appendingPathComponent(bundledModel.filename)
        try Data("bad content".utf8).write(to: path)
        let sameSizeWrongHash = WhisperModel(
            id: UUID(),
            name: "wrong-hash",
            displayName: "Wrong hash",
            size: "11 bytes",
            downloadURL: "https://example.com/wrong-hash.bin",
            expectedByteCount: 11,
            sha256: String(repeating: "0", count: 64),
            isMultilingual: true,
            description: "Test model"
        )

        XCTAssertThrowsError(try ModelFileValidator.validate(fileAt: path, for: sameSizeWrongHash)) { error in
            guard case ModelValidationError.checksumMismatch = error else {
                return XCTFail("Expected checksumMismatch, got \(error)")
            }
        }
    }

    func testAsyncValidatorPropagatesCancellation() async throws {
        let path = tempDirectory.appendingPathComponent(bundledModel.filename)
        try validModelContents.write(to: path)

        let validation = Task {
            try await ModelFileValidator.validateAsync(fileAt: path, for: bundledModel)
        }
        validation.cancel()

        do {
            try await validation.value
            XCTFail("Expected validation to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testResponseValidatorRejectsHTTPError() throws {
        let path = tempDirectory.appendingPathComponent("response-error.bin")
        try validModelContents.write(to: path)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/model.bin")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Length": "11"]
        )!

        XCTAssertThrowsError(
            try ModelDownloadResponseValidator.validate(response, fileAt: path)
        ) { error in
            guard case ModelDownloadError.invalidHTTPStatus(404) = error else {
                return XCTFail("Expected invalidHTTPStatus, got \(error)")
            }
        }
    }

    func testResponseValidatorRejectsIncompleteBody() throws {
        let path = tempDirectory.appendingPathComponent("response-size.bin")
        try validModelContents.write(to: path)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/model.bin")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "12"]
        )!

        XCTAssertThrowsError(
            try ModelDownloadResponseValidator.validate(response, fileAt: path)
        ) { error in
            guard case ModelDownloadError.responseSizeMismatch(expected: 12, actual: 11) = error else {
                return XCTFail("Expected responseSizeMismatch, got \(error)")
            }
        }
    }
}
