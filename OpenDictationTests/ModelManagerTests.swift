@testable import OpenDictation
import XCTest

@MainActor
final class ModelManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var sut: ModelManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a unique temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        sut = ModelManager(modelsDirectory: tempDirectory)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }
    
    func testInitializationCreatesDirectory() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
    }
    
    func testLoadDownloadedModels() throws {
        // Given: Create a dummy model file
        let modelFile = tempDirectory.appendingPathComponent("ggml-tiny.bin")
        try "dummy content".write(to: modelFile, atomically: true, encoding: .utf8)
        
        // When
        sut.loadDownloadedModels()
        
        // Then
        XCTAssertEqual(sut.downloadedModels.count, 1)
        XCTAssertEqual(sut.downloadedModels.first?.name, "ggml-tiny")
    }
    
    func testIsDownloaded() throws {
        let model = PredefinedModels.bundled
        XCTAssertFalse(sut.isDownloaded(model))
        
        let path = tempDirectory.appendingPathComponent(model.filename)
        try "dummy".write(to: path, atomically: true, encoding: .utf8)
        
        sut.loadDownloadedModels()
        XCTAssertTrue(sut.isDownloaded(model))
    }
    
    func testValidateSelectedModelFallsBackToBundled() throws {
        // Given: We have a bundled model file on disk
        let bundled = PredefinedModels.bundled
        let bundledPath = tempDirectory.appendingPathComponent(bundled.filename)
        try "bundled content".write(to: bundledPath, atomically: true, encoding: .utf8)
        sut.loadDownloadedModels()
        
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
}
