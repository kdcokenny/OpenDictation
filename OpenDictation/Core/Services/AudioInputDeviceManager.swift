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
            devices = try loadDevices()
        } catch {
            devices = []
            logger.error("Couldn't load audio input devices: \(error.localizedDescription)")
        }
    }

    func device(withUID uid: String) -> AudioInputDevice? {
        devices.first { $0.uid == uid }
    }

    func isInputDeviceAvailable(withUID uid: String) -> Bool {
        do {
            guard let deviceID = try Self.deviceID(forUID: uid) else { return false }
            return try Self.isUsableInputDevice(deviceID)
        } catch {
            logger.warning("Couldn't validate audio input device \(uid): \(error.localizedDescription)")
            return false
        }
    }

    private func loadDevices() throws -> [AudioInputDevice] {
        let deviceIDs = try Self.audioDeviceIDs()
        return Self.loadDevices(
            from: deviceIDs,
            deviceProvider: Self.inputDevice
        ) { [logger] deviceID, error in
            logger.warning("Skipping audio device \(deviceID): \(error.localizedDescription)")
        }
    }

    static func loadDevices(
        from deviceIDs: [AudioDeviceID],
        deviceProvider: (AudioDeviceID) throws -> AudioInputDevice?,
        onFailure: (AudioDeviceID, Error) -> Void
    ) -> [AudioInputDevice] {
        var seenUIDs = Set<String>()
        var devices: [AudioInputDevice] = []

        for deviceID in deviceIDs {
            do {
                guard let device = try deviceProvider(deviceID),
                      seenUIDs.insert(device.uid).inserted else {
                    continue
                }
                devices.append(device)
            } catch {
                onFailure(deviceID, error)
            }
        }

        return devices.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder == .orderedSame {
                return $0.uid < $1.uid
            }
            return nameOrder == .orderedAscending
        }
    }

    private static func inputDevice(_ deviceID: AudioDeviceID) throws -> AudioInputDevice? {
        guard try isUsableInputDevice(deviceID) else { return nil }

        let uid = try stringProperty(kAudioDevicePropertyDeviceUID, of: deviceID)
        let name = try stringProperty(kAudioObjectPropertyName, of: deviceID)
        return AudioInputDevice(uid: uid, name: name)
    }

    private static func isUsableInputDevice(_ deviceID: AudioDeviceID) throws -> Bool {
        guard try hasInputStreams(deviceID) else { return false }
        guard try isAlive(deviceID) else { return false }
        return try !isHidden(deviceID)
    }

    private static func deviceID(forUID uid: String) throws -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceUID: CFString = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &deviceUID) { deviceUIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.stride),
                deviceUIDPointer,
                &dataSize,
                &deviceID
            )
        }
        try checkStatus(status, operation: "find an audio device by UID")
        return deviceID == AudioDeviceID(kAudioObjectUnknown) ? nil : deviceID
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
