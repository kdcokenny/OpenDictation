import Foundation
import XCTest
@testable import OpenDictation

final class CloudTranscriptionProviderTests: XCTestCase {

    private var audioURL: URL!

    override func setUp() {
        super.setUp()
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudTranscriptionProviderTests-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try! Data([0, 1, 2, 3]).write(to: audioURL)
    }

    override func tearDown() {
        if let audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil

        super.tearDown()
    }

    func testTransientTimeoutRetriesAndReturnsTranscript() async throws {
        let attempts = AttemptCounter()
        let sut = CloudTranscriptionProvider(apiKeyProvider: Self.testAPIKey) { _, _ in
            if attempts.increment() == 1 {
                throw URLError(.timedOut)
            }

            return try Self.successResponse(text: " Recovered transcript ")
        }

        let text = try await sut.transcribe(audioURL: audioURL, context: .prose)

        XCTAssertEqual(text, "Recovered transcript")
        XCTAssertEqual(attempts.count, 2)
    }

    func testRepeatedTimeoutReturnsSimpleTimeoutMessage() async throws {
        let attempts = AttemptCounter()
        let sut = CloudTranscriptionProvider(apiKeyProvider: Self.testAPIKey) { _, _ in
            attempts.increment()
            throw URLError(.timedOut)
        }

        do {
            _ = try await sut.transcribe(audioURL: audioURL, context: .prose)
            XCTFail("Expected transcription to time out")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Transcription timed out.")
            XCTAssertEqual(attempts.count, 2)
        }
    }

    func testNonTransientUploadErrorDoesNotRetry() async throws {
        let attempts = AttemptCounter()
        let sut = CloudTranscriptionProvider(apiKeyProvider: Self.testAPIKey) { _, _ in
            attempts.increment()
            throw URLError(.userAuthenticationRequired)
        }

        do {
            _ = try await sut.transcribe(audioURL: audioURL, context: .prose)
            XCTFail("Expected transcription to fail")
        } catch {
            XCTAssertEqual(attempts.count, 1)
        }
    }

    func testHTTPErrorDoesNotRetry() async throws {
        let attempts = AttemptCounter()
        let sut = CloudTranscriptionProvider(apiKeyProvider: Self.testAPIKey) { _, _ in
            attempts.increment()
            return try Self.response(
                statusCode: 401,
                body: #"{"error":{"message":"Invalid API key","type":"invalid_request_error","code":"invalid_api_key"}}"#
            )
        }

        do {
            _ = try await sut.transcribe(audioURL: audioURL, context: .prose)
            XCTFail("Expected API request failure")
        } catch {
            XCTAssertEqual(attempts.count, 1)
            XCTAssertTrue(error.localizedDescription.contains("Server error (401): Invalid API key"))
        }
    }

    private static func successResponse(text: String) throws -> (Data, URLResponse) {
        try response(statusCode: 200, body: #"{"text":"\#(text)"}"#)
    }

    private static func testAPIKey() -> String? {
        "test-api-key"
    }

    private static func response(statusCode: Int, body: String) throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(URL(string: "https://api.openai.com/v1/audio/transcriptions"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
        return (Data(body.utf8), response)
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
