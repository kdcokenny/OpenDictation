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

    func testAudioLoaderReadsWAVWithExtraChunkAndResamplesTo16kHzMono() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-loader-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try makeStereoWAVWithJunkChunk(sampleRate: 48_000, frameCount: 4_800)
            .write(to: url)

        let samples = try loadAudioSamples(from: url)

        XCTAssertTrue((1_500...1_700).contains(samples.count))
        XCTAssertTrue(samples.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.4)
    }

    func testAudioLoaderRejectsInvalidAudio() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-audio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a wave file".utf8).write(to: url)

        XCTAssertThrowsError(try loadAudioSamples(from: url)) { error in
            XCTAssertEqual(error as? WhisperError, .audioLoadFailed)
        }
    }

    func testWhisperCancellationHandlerSignalsTheAbortState() async throws {
        let state = WhisperCancellationState()
        let transcription = Task.detached {
            await withTaskCancellationHandler {
                while !state.isCancelled {
                    await Task.yield()
                }
                return state.isCancelled
            } onCancel: {
                state.cancel()
            }
        }

        await Task.yield()
        transcription.cancel()
        let observedCancellation = await transcription.value

        XCTAssertTrue(observedCancellation)
    }

    private func makeStereoWAVWithJunkChunk(
        sampleRate: UInt32,
        frameCount: Int
    ) -> Data {
        let channelCount: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let bytesPerFrame = UInt16(channelCount * bitsPerSample / 8)

        var audioData = Data()
        for index in 0..<frameCount {
            let phase = Double(index) * 440 * 2 * .pi / Double(sampleRate)
            let sample = Int16(sin(phase) * Double(Int16.max) * 0.5)
            appendLittleEndian(UInt16(bitPattern: sample), to: &audioData)
            appendLittleEndian(UInt16(bitPattern: sample), to: &audioData)
        }

        var payload = Data("WAVE".utf8)
        payload.append(Data("JUNK".utf8))
        appendLittleEndian(UInt32(3), to: &payload)
        payload.append(contentsOf: [1, 2, 3, 0])

        payload.append(Data("fmt ".utf8))
        appendLittleEndian(UInt32(16), to: &payload)
        appendLittleEndian(UInt16(1), to: &payload)
        appendLittleEndian(channelCount, to: &payload)
        appendLittleEndian(sampleRate, to: &payload)
        appendLittleEndian(sampleRate * UInt32(bytesPerFrame), to: &payload)
        appendLittleEndian(bytesPerFrame, to: &payload)
        appendLittleEndian(bitsPerSample, to: &payload)

        payload.append(Data("data".utf8))
        appendLittleEndian(UInt32(audioData.count), to: &payload)
        payload.append(audioData)

        var wav = Data("RIFF".utf8)
        appendLittleEndian(UInt32(payload.count), to: &wav)
        wav.append(payload)
        return wav
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
