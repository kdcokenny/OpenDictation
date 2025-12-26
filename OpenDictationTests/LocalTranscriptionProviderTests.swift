import XCTest
@testable import OpenDictation

@MainActor
final class LocalTranscriptionProviderTests: XCTestCase {
    
    private var sut: LocalTranscriptionProvider!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = LocalTranscriptionProvider.shared
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testInitialization() {
        XCTAssertNotNil(sut)
    }
}
