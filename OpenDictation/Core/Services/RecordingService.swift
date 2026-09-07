import AudioToolbox
import AVFoundation
import Combine
import os.log

enum RecordingError: Error, LocalizedError {
    case microphonePermissionDenied
    case inputDeviceUnavailable
    case alreadyRecording
    case setupFailed(Error)
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access required. Allow it in System Settings."
        case .inputDeviceUnavailable:
            return "The selected microphone is unavailable. Reconnect it or choose another microphone in Settings."
        case .alreadyRecording:
            return "A recording is already in progress."
        case .setupFailed(let error):
            return "Couldn't start recording: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording stopped unexpectedly: \(error.localizedDescription)"
        }
    }
}

/// Records 16 kHz, mono, 16-bit PCM WAV files for transcription.
@MainActor
final class RecordingService: NSObject, ObservableObject {
    static let shared = RecordingService()

    @Published private(set) var audioLevel: Float = 0

    /// Called after an active recording fails and its partial file is removed.
    var onRecordingError: ((RecordingError, URL?) -> Void)?

    private enum AudioMetering {
        static let minimumDecibels: Float = -35
        static let maximumDecibels: Float = -20
        static let amplitudeExponent: Float = 0.5
        static let visualBoost: Float = 2.5
        static let smoothingFactor: Float = 0.8
        static let updateInterval: TimeInterval = 1.0 / 60.0
    }

    private let logger = Logger.app(category: "RecordingService")
    private var recorder: AudioQueueRecorder?
    private var activeRecordingID: UUID?
    private var levelTimer: Timer?
    private var recordingURL: URL?

    private override init() {
        super.init()
    }

    /// Starts recording with the microphone saved in user preferences.
    func startRecording() throws {
        let inputDeviceUID = UserDefaults.standard.string(
            forKey: AudioInputDeviceManager.preferenceKey
        ) ?? ""
        try startRecording(inputDeviceUID: inputDeviceUID)
    }

    /// Starts recording with a stable Core Audio device UID.
    /// Pass an empty UID to use the current system default input.
    func startRecording(inputDeviceUID: String) throws {
        guard checkMicrophonePermission() else {
            logger.error("Microphone permission denied")
            throw RecordingError.microphonePermissionDenied
        }
        guard recorder == nil else {
            throw RecordingError.alreadyRecording
        }

        if !inputDeviceUID.isEmpty {
            guard AudioInputDeviceManager.shared.isInputDeviceAvailable(
                withUID: inputDeviceUID
            ) else {
                throw RecordingError.inputDeviceUnavailable
            }
        }

        deleteRecording()

        let recordingID = UUID()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation_\(recordingID.uuidString).wav")
        let newRecorder = AudioQueueRecorder(url: url) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleRecordingFailure(error, recordingID: recordingID)
            }
        }

        do {
            try newRecorder.start(inputDeviceUID: inputDeviceUID)
        } catch {
            throw RecordingError.setupFailed(error)
        }

        recorder = newRecorder
        activeRecordingID = recordingID
        recordingURL = url
        startLevelMetering()
        logger.info("Recording started: \(url.path)")
    }

    /// Stops recording and returns its file after the WAV header is finalized.
    @discardableResult
    func stopRecording() -> URL? {
        stopLevelMetering()
        guard let recorder else { return nil }

        let stopError = recorder.stop()
        self.recorder = nil
        activeRecordingID = nil
        audioLevel = 0

        if let stopError {
            logger.error("Couldn't stop recording cleanly: \(stopError.localizedDescription)")
            if let recordingURL {
                deleteRecording(at: recordingURL)
            }
            return nil
        }

        if let recordingURL {
            logger.info("Recording stopped: \(recordingURL.path)")
        }
        return recordingURL
    }

    func deleteRecording() {
        guard let recordingURL else { return }
        deleteRecording(at: recordingURL)
    }

    /// Deletes exactly the supplied file. A different active recording remains tracked.
    func deleteRecording(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("Recording deleted: \(url.path)")
        } catch CocoaError.fileNoSuchFile {
            logger.debug("Recording was already deleted: \(url.path)")
        } catch {
            logger.warning("Failed to delete recording at \(url.path): \(error.localizedDescription)")
        }

        if recordingURL == url {
            recordingURL = nil
        }
    }

    private func handleRecordingFailure(_ error: Error, recordingID: UUID) {
        guard activeRecordingID == recordingID else { return }

        stopLevelMetering()
        _ = recorder?.stop()
        recorder = nil
        activeRecordingID = nil
        audioLevel = 0

        let failedURL = recordingURL
        if let failedURL {
            deleteRecording(at: failedURL)
        }

        let recordingError = RecordingError.recordingFailed(error)
        logger.error("\(recordingError.localizedDescription)")
        onRecordingError?(recordingError, failedURL)
    }

    private func startLevelMetering() {
        levelTimer = Timer.scheduledTimer(
            withTimeInterval: AudioMetering.updateInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAudioLevel()
            }
        }
    }

    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func updateAudioLevel() {
        guard let averagePower = recorder?.averagePower else {
            audioLevel = 0
            return
        }
        guard averagePower >= AudioMetering.minimumDecibels else {
            audioLevel = 0
            return
        }

        let clampedPower = min(averagePower, AudioMetering.maximumDecibels)
        let amplitude = pow(10, 0.05 * clampedPower)
        let minimumAmplitude = pow(10, 0.05 * AudioMetering.minimumDecibels)
        let maximumAmplitude = pow(10, 0.05 * AudioMetering.maximumDecibels)
        let normalized = (amplitude - minimumAmplitude) / (maximumAmplitude - minimumAmplitude)
        let boostedLevel = min(
            pow(normalized, AudioMetering.amplitudeExponent) * AudioMetering.visualBoost,
            1
        )

        let oldWeight = 1 - AudioMetering.smoothingFactor
        audioLevel = audioLevel * oldWeight + boostedLevel * AudioMetering.smoothingFactor
    }

    private func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

private final class AudioQueueRecorder: @unchecked Sendable {
    private enum Format {
        static let sampleRate: Float64 = 16_000
        static let channelCount: UInt32 = 1
        static let bitsPerChannel: UInt32 = 16
        static let bytesPerFrame: UInt32 = 2
        static let framesPerPacket: UInt32 = 1
        static let bufferDuration: Float64 = 0.2
        static let bufferCount = 3

        static var streamDescription: AudioStreamBasicDescription {
            AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: bytesPerFrame,
                mFramesPerPacket: framesPerPacket,
                mBytesPerFrame: bytesPerFrame,
                mChannelsPerFrame: channelCount,
                mBitsPerChannel: bitsPerChannel,
                mReserved: 0
            )
        }

        static var bufferByteSize: UInt32 {
            UInt32(sampleRate * bufferDuration) * bytesPerFrame
        }
    }

    private let url: URL
    private let failureHandler: @Sendable (AudioQueueOperationError) -> Void
    private let callbackQueue = DispatchQueue(label: "com.opendictation.audio-input")
    private let lock = NSLock()

    private var audioQueue: AudioQueueRef?
    private var audioFile: AudioFileID?
    private var nextPacket: Int64 = 0
    private var acceptsBuffers = false
    private var isStopping = false
    private var didReportFailure = false
    private var recordingError: AudioQueueOperationError?
    private var isRunningListenerInstalled = false

    init(
        url: URL,
        failureHandler: @escaping @Sendable (AudioQueueOperationError) -> Void
    ) {
        self.url = url
        self.failureHandler = failureHandler
    }

    func start(inputDeviceUID: String) throws {
        var format = Format.streamDescription
        var createdQueue: AudioQueueRef?

        try checkStatus(
            AudioQueueNewInputWithDispatchQueue(
                &createdQueue,
                &format,
                0,
                callbackQueue
            ) { [weak self] queue, buffer, _, packetCount, _ in
                self?.processBuffer(queue, buffer: buffer, packetCount: packetCount)
            },
            operation: "create the input queue"
        )
        guard let createdQueue else {
            throw AudioQueueOperationError(
                operation: "create the input queue",
                status: kAudioQueueErr_InvalidQueueType
            )
        }
        audioQueue = createdQueue

        do {
            if !inputDeviceUID.isEmpty {
                try selectInputDevice(inputDeviceUID, on: createdQueue)
            }

            var file: AudioFileID?
            try checkStatus(
                AudioFileCreateWithURL(
                    url as CFURL,
                    kAudioFileWAVEType,
                    &format,
                    .eraseFile,
                    &file
                ),
                operation: "create the WAV file"
            )
            guard let file else {
                throw AudioQueueOperationError(
                    operation: "create the WAV file",
                    status: kAudioFileUnspecifiedError
                )
            }
            audioFile = file

            var meteringEnabled: UInt32 = 1
            try checkStatus(
                AudioQueueSetProperty(
                    createdQueue,
                    kAudioQueueProperty_EnableLevelMetering,
                    &meteringEnabled,
                    UInt32(MemoryLayout<UInt32>.size)
                ),
                operation: "enable input metering"
            )

            let listenerContext = Unmanaged.passUnretained(self).toOpaque()
            try checkStatus(
                AudioQueueAddPropertyListener(
                    createdQueue,
                    kAudioQueueProperty_IsRunning,
                    audioQueueRunningStateChanged,
                    listenerContext
                ),
                operation: "monitor the input queue"
            )
            isRunningListenerInstalled = true

            for _ in 0..<Format.bufferCount {
                var buffer: AudioQueueBufferRef?
                try checkStatus(
                    AudioQueueAllocateBuffer(
                        createdQueue,
                        Format.bufferByteSize,
                        &buffer
                    ),
                    operation: "allocate an input buffer"
                )
                guard let buffer else {
                    throw AudioQueueOperationError(
                        operation: "allocate an input buffer",
                        status: kAudioQueueErr_InvalidBuffer
                    )
                }
                try checkStatus(
                    AudioQueueEnqueueBuffer(createdQueue, buffer, 0, nil),
                    operation: "enqueue an input buffer"
                )
            }

            lock.lock()
            acceptsBuffers = true
            lock.unlock()
            try checkStatus(
                AudioQueueStart(createdQueue, nil),
                operation: "start the input queue"
            )
        } catch {
            lock.lock()
            acceptsBuffers = false
            lock.unlock()
            disposePreparedResources()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    var averagePower: Float? {
        lock.lock()
        defer { lock.unlock() }

        guard acceptsBuffers, let audioQueue else { return nil }
        var meterState = AudioQueueLevelMeterState()
        var dataSize = UInt32(MemoryLayout<AudioQueueLevelMeterState>.size)
        let status = AudioQueueGetProperty(
            audioQueue,
            kAudioQueueProperty_CurrentLevelMeterDB,
            &meterState,
            &dataSize
        )
        guard status == noErr else { return nil }
        return meterState.mAveragePower
    }

    func stop() -> Error? {
        lock.lock()
        let queue = audioQueue
        let file = audioFile
        let listenerWasInstalled = isRunningListenerInstalled
        isStopping = true
        lock.unlock()

        var firstError: Error?
        if let queue {
            let flushStatus = AudioQueueFlush(queue)
            if flushStatus != noErr {
                firstError = AudioQueueOperationError(
                    operation: "flush final recorded audio",
                    status: flushStatus
                )
            }

            let stopStatus = AudioQueueStop(queue, true)
            if firstError == nil, stopStatus != noErr {
                firstError = AudioQueueOperationError(
                    operation: "stop the input queue",
                    status: stopStatus
                )
            }

            if listenerWasInstalled {
                let listenerContext = Unmanaged.passUnretained(self).toOpaque()
                AudioQueueRemovePropertyListener(
                    queue,
                    kAudioQueueProperty_IsRunning,
                    audioQueueRunningStateChanged,
                    listenerContext
                )
            }

            let disposeStatus = AudioQueueDispose(queue, true)
            if firstError == nil, disposeStatus != noErr {
                firstError = AudioQueueOperationError(
                    operation: "dispose the input queue",
                    status: disposeStatus
                )
            }
        }

        lock.lock()
        acceptsBuffers = false
        audioQueue = nil
        audioFile = nil
        isRunningListenerInstalled = false
        isStopping = false
        let callbackError = recordingError
        lock.unlock()

        if firstError == nil {
            firstError = callbackError
        }

        if let file {
            let closeStatus = AudioFileClose(file)
            if firstError == nil, closeStatus != noErr {
                firstError = AudioQueueOperationError(
                    operation: "finalize the WAV file",
                    status: closeStatus
                )
            }
        }
        return firstError
    }

    private func processBuffer(
        _ queue: AudioQueueRef,
        buffer: AudioQueueBufferRef,
        packetCount: UInt32
    ) {
        lock.lock()
        guard acceptsBuffers, let audioFile else {
            lock.unlock()
            return
        }

        var packetsToWrite = packetCount
        if packetsToWrite == 0 {
            packetsToWrite = buffer.pointee.mAudioDataByteSize / Format.bytesPerFrame
        }

        let writeStatus = AudioFileWritePackets(
            audioFile,
            false,
            buffer.pointee.mAudioDataByteSize,
            nil,
            nextPacket,
            &packetsToWrite,
            buffer.pointee.mAudioData
        )
        if writeStatus == noErr {
            nextPacket += Int64(packetsToWrite)
        }

        let enqueueStatus: OSStatus
        if writeStatus == noErr, acceptsBuffers, !isStopping {
            enqueueStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        } else {
            enqueueStatus = noErr
        }

        let failureStatus = writeStatus != noErr ? writeStatus : enqueueStatus
        let bufferError: AudioQueueOperationError?
        if failureStatus == noErr {
            bufferError = nil
        } else {
            bufferError = AudioQueueOperationError(
                operation: writeStatus != noErr ? "write recorded audio" : "continue recording",
                status: failureStatus
            )
            acceptsBuffers = false
            recordingError = bufferError
        }
        lock.unlock()

        guard let bufferError else { return }
        reportFailureOnce(bufferError)
    }

    private func selectInputDevice(_ uid: String, on queue: AudioQueueRef) throws {
        var deviceUID: CFString = uid as CFString
        try checkStatus(
            AudioQueueSetProperty(
                queue,
                kAudioQueueProperty_CurrentDevice,
                &deviceUID,
                UInt32(MemoryLayout<CFString>.stride)
            ),
            operation: "select the microphone"
        )
    }

    fileprivate func runningStateChanged(on queue: AudioQueueRef) {
        lock.lock()
        guard acceptsBuffers else {
            lock.unlock()
            return
        }

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioQueueGetProperty(
            queue,
            kAudioQueueProperty_IsRunning,
            &isRunning,
            &dataSize
        )
        let stoppedUnexpectedly = !isStopping && status == noErr && isRunning == 0
        let stateReadFailed = !isStopping && status != noErr
        let stateError: AudioQueueOperationError?
        if stateReadFailed {
            stateError = AudioQueueOperationError(
                operation: "read the input queue state",
                status: status
            )
        } else if stoppedUnexpectedly {
            stateError = AudioQueueOperationError(
                operation: "keep the selected microphone connected",
                status: kAudioQueueErr_InvalidDevice
            )
        } else {
            stateError = nil
        }
        if stoppedUnexpectedly || stateReadFailed {
            acceptsBuffers = false
            recordingError = stateError
        }
        lock.unlock()

        guard let stateError else { return }
        reportFailureOnce(stateError)
    }

    private func reportFailureOnce(_ error: AudioQueueOperationError) {
        lock.lock()
        guard !didReportFailure else {
            lock.unlock()
            return
        }
        didReportFailure = true
        lock.unlock()
        failureHandler(error)
    }

    private func disposePreparedResources() {
        if let audioQueue {
            if isRunningListenerInstalled {
                let listenerContext = Unmanaged.passUnretained(self).toOpaque()
                AudioQueueRemovePropertyListener(
                    audioQueue,
                    kAudioQueueProperty_IsRunning,
                    audioQueueRunningStateChanged,
                    listenerContext
                )
                isRunningListenerInstalled = false
            }
            AudioQueueDispose(audioQueue, true)
            self.audioQueue = nil
        }
        if let audioFile {
            AudioFileClose(audioFile)
            self.audioFile = nil
        }
    }

    private func checkStatus(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioQueueOperationError(operation: operation, status: status)
        }
    }
}

private func audioQueueRunningStateChanged(
    _ userData: UnsafeMutableRawPointer?,
    _ queue: AudioQueueRef,
    _ propertyID: AudioQueuePropertyID
) {
    guard propertyID == kAudioQueueProperty_IsRunning, let userData else { return }
    let recorder = Unmanaged<AudioQueueRecorder>.fromOpaque(userData).takeUnretainedValue()
    recorder.runningStateChanged(on: queue)
}

private struct AudioQueueOperationError: LocalizedError, Sendable {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "Core Audio couldn't \(operation) (error \(status))."
    }
}
