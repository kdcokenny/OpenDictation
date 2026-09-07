import CoreAudio
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

    @MainActor
    func testDeviceEnumerationSkipsOnlyTheDeviceThatDisappears() {
        struct DeviceDisappeared: Error {}

        let healthyDevice = AudioInputDevice(uid: "healthy", name: "Working microphone")
        var failedDeviceIDs: [AudioDeviceID] = []
        let devices = AudioInputDeviceManager.loadDevices(
            from: [1, 2],
            deviceProvider: { deviceID in
                if deviceID == 1 {
                    throw DeviceDisappeared()
                }
                return healthyDevice
            },
            onFailure: { deviceID, _ in
                failedDeviceIDs.append(deviceID)
            }
        )

        XCTAssertEqual(devices, [healthyDevice])
        XCTAssertEqual(failedDeviceIDs, [1])
    }
}
