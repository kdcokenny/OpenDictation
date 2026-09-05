import Combine
import CoreAudio
import Foundation
import os.log

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let uid: String
    let name: String

    var id: String { uid }
}

@MainActor
final class AudioInputDeviceManager: ObservableObject {
    static let shared = AudioInputDeviceManager()
    static let preferenceKey = "inputDeviceUID"

    @Published private(set) var devices: [AudioInputDevice] = []

    private let logger = Logger.app(category: "AudioInputDeviceManager")

    private init() {
        refresh()
    }

    func refresh() {
        do {
            devices = try Self.loadDevices()
        } catch {
            devices = []
            logger.error("Couldn't load audio input devices: \(error.localizedDescription)")
        }
    }

    func device(withUID uid: String) -> AudioInputDevice? {
        devices.first { $0.uid == uid }
    }

    private static func loadDevices() throws -> [AudioInputDevice] {
        let deviceIDs = try audioDeviceIDs()
        var seenUIDs = Set<String>()

        return try deviceIDs.compactMap { deviceID in
            guard try hasInputStreams(deviceID),
                  try isAlive(deviceID),
                  !(try isHidden(deviceID)) else {
                return nil
            }

            let uid = try stringProperty(kAudioDevicePropertyDeviceUID, of: deviceID)
            guard seenUIDs.insert(uid).inserted else { return nil }

            let name = try stringProperty(kAudioObjectPropertyName, of: deviceID)
            return AudioInputDevice(uid: uid, name: name)
        }
        .sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder == .orderedSame {
                return $0.uid < $1.uid
            }
            return nameOrder == .orderedAscending
        }
    }

    private static func audioDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        try checkStatus(
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize
            ),
            operation: "read the audio device list"
        )

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status = deviceIDs.withUnsafeMutableBytes { storage in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                storage.baseAddress!
            )
        }
        try checkStatus(status, operation: "load the audio device list")
        return deviceIDs
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        try checkStatus(
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &dataSize
            ),
            operation: "inspect an audio device"
        )
        return dataSize >= MemoryLayout<AudioStreamID>.size
    }

    private static func isAlive(_ deviceID: AudioDeviceID) throws -> Bool {
        try uint32Property(kAudioDevicePropertyDeviceIsAlive, of: deviceID) != 0
    }

    private static func isHidden(_ deviceID: AudioDeviceID) throws -> Bool {
        let selector = kAudioDevicePropertyIsHidden
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        return try uint32Property(selector, of: deviceID) != 0
    }

    private static func uint32Property(
        _ selector: AudioObjectPropertySelector,
        of deviceID: AudioDeviceID
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        try checkStatus(
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                &value
            ),
            operation: "read an audio device property"
        )
        return value
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        of deviceID: AudioDeviceID
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.stride)

        try checkStatus(
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                &value
            ),
            operation: "read an audio device name"
        )
        return value as String
    }

    private static func checkStatus(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CoreAudioOperationError(operation: operation, status: status)
        }
    }
}

private struct CoreAudioOperationError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "Core Audio couldn't \(operation) (error \(status))."
    }
}
