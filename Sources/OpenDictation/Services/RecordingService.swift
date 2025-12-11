import AVFoundation
import Combine
import os.log

/// Errors that can occur during recording.
enum RecordingError: Error, LocalizedError {
    case microphonePermissionDenied
    case setupFailed(Error)
    case recordingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access required. Allow in System Settings."
        case .setupFailed(let error):
            return "Couldn't start recording: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording stopped unexpectedly: \(error.localizedDescription)"
        }
    }
}

/// Service for recording audio using AVFoundation.
///
/// Records to a temporary WAV file (LinearPCM format) optimized for Whisper transcription.
/// Uses 16kHz mono audio which is the native format for Whisper models.
final class RecordingService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = RecordingService()
    
    // MARK: - Logger
    
    private let logger = Logger(subsystem: "com.opendictation", category: "RecordingService")
    
    // MARK: - Published Properties
    
    /// Current audio level (0.0 to 1.0) for waveform visualization.
    @Published private(set) var audioLevel: Float = 0
    
    // MARK: - Constants
    
    private enum AudioMetering {
        /// Silence threshold in dB
        static let minDecibels: Float = -35.0
        /// Speech peak threshold in dB
        static let maxDecibels: Float = -20.0
        /// Exponent for amplitude curve (sqrt for natural feel)
        static let amplitudeExponent: Float = 0.5
        /// Boost factor to fill visual range for normal speech
        static let visualBoost: Float = 2.5
        /// Smoothing factor (0.8 = 80% new value, 20% old)
        static let smoothingFactor: Float = 0.8
    }
    
    // MARK: - Private Properties
    
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Starts recording audio.
    ///
    /// - Throws: `RecordingError` if recording cannot start.
    func startRecording() throws {
        // Check microphone permission
        guard checkMicrophonePermission() else {
            logger.error("Microphone permission denied")
            throw RecordingError.microphonePermissionDenied
        }
        
        // Stop any existing recording and clean up
        if audioRecorder != nil {
            logger.info("Stopping previous recording")
            audioRecorder?.stop()
            audioRecorder = nil
        }
        stopLevelMetering()
        
        // Create temporary file URL - use .wav extension for LinearPCM
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dictation_\(UUID().uuidString).wav"
        let url = tempDir.appendingPathComponent(fileName)
        recordingURL = url
        
        // Recording settings - LinearPCM (WAV) at 16kHz mono
        // This is the native format for Whisper and most reliable across platforms
        // Reference: whisper.cpp uses exactly these settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,  // 16kHz is optimal for Whisper
            AVNumberOfChannelsKey: 1,   // Mono is sufficient for speech
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        // Create recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            guard audioRecorder?.prepareToRecord() == true else {
                throw RecordingError.setupFailed(NSError(domain: "RecordingService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder"]))
            }
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.setupFailed(error)
        }
        
        // Start recording
        guard audioRecorder?.record() == true else {
            let recorderError = audioRecorder?.url != nil ? "Recorder exists but won't start" : "Recorder is nil"
            logger.error("record() failed: \(recorderError)")
            throw RecordingError.recordingFailed(NSError(domain: "RecordingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"]))
        }
        
        startLevelMetering()
        
        logger.info("Recording started: \(url.path)")
    }
    
    /// Stops recording and returns the URL to the recorded audio file.
    ///
    /// - Returns: URL to the recorded audio file, or nil if no recording.
    @discardableResult
    func stopRecording() -> URL? {
        stopLevelMetering()
        
        guard let recorder = audioRecorder else { return nil }
        
        recorder.stop()
        audioRecorder = nil
        audioLevel = 0
        
        let url = recordingURL
        
        if let url = url {
            logger.info("Recording stopped: \(url.path)")
        }
        
        return url
    }
    
    /// Deletes the recording file.
    func deleteRecording() {
        guard let url = recordingURL else { return }
        
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("Recording deleted")
        } catch {
            logger.warning("Failed to delete recording at \(url.path): \(error.localizedDescription)")
        }
        recordingURL = nil
    }
    
    // MARK: - Level Metering
    
    private func startLevelMetering() {
        // Update audio level at 60fps for responsive waveform (matches CADisplayLink)
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }
    
    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
            return
        }
        
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        
        if averagePower < AudioMetering.minDecibels {
            audioLevel = 0
            return
        }
        
        // Clamp to speech range
        let clampedPower = min(averagePower, AudioMetering.maxDecibels)
        
        // Apple formula: dB → amplitude → normalize → sqrt
        let amplitude = pow(10.0, 0.05 * clampedPower)
        let minAmplitude = pow(10.0, 0.05 * AudioMetering.minDecibels)
        let maxAmplitude = pow(10.0, 0.05 * AudioMetering.maxDecibels)
        let normalized = (amplitude - minAmplitude) / (maxAmplitude - minAmplitude)
        
        // Boost to fill visual range for normal speech
        let newLevel = min(pow(normalized, AudioMetering.amplitudeExponent) * AudioMetering.visualBoost, 1.0)
        
        // Light smoothing to reduce jitter
        let oldWeight = 1.0 - AudioMetering.smoothingFactor
        audioLevel = audioLevel * oldWeight + newLevel * AudioMetering.smoothingFactor
    }
    
    // MARK: - Permissions
    
    /// Checks if microphone permission is granted.
    ///
    /// This only checks status - it does not request permission.
    /// Permission should be requested during app setup via `PermissionsManager.requestMicrophone()`.
    private func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

// MARK: - AVAudioRecorderDelegate

extension RecordingService: AVAudioRecorderDelegate {
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            logger.warning("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            logger.error("Encoding error: \(error.localizedDescription)")
        }
    }
}
