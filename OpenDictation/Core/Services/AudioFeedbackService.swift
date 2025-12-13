import AppKit
import CoreAudio
import os.log

// AudioDeviceDuck is a semi-private CoreAudio API used by FaceTime/Siri for ducking
// It's not in public headers but exists in the framework
@_silgen_name("AudioDeviceDuck")
func AudioDeviceDuck(
    _ inDevice: AudioDeviceID,
    _ inDuckedLevel: Float32,
    _ inStartTime: UnsafePointer<AudioTimeStamp>?,
    _ inRampDuration: Float32
) -> OSStatus

/// Provides audio feedback for dictation events.
///
/// Uses the same sounds as macOS native dictation, bundled from system files.
/// Also handles volume ducking during recording using CoreAudio's AudioDeviceDuck API
/// (same mechanism used by FaceTime/Siri) to lower other audio while our sounds play.
final class AudioFeedbackService {
    
    // MARK: - Logger
    
    private let logger = Logger(subsystem: "com.opendictation", category: "AudioFeedback")
    
    // MARK: - Constants
    
    private enum VolumeDucking {
        /// Ducked volume level (~10% / -20dB)
        static let duckedLevel: Float32 = 0.1
        /// Normal volume level (full)
        static let normalLevel: Float32 = 1.0
        /// Ramp duration when ducking (quick)
        static let duckRampDuration: Float32 = 0.1
        /// Ramp duration when restoring (smooth transition)
        static let restoreRampDuration: Float32 = 0.3
    }
    
    // MARK: - Sound Players
    
    private var startSound: NSSound?
    private var endSound: NSSound?
    private var errorSound: NSSound?
    
    // MARK: - Volume Ducking State
    
    /// Whether we currently have the volume ducked
    private var isVolumeDucked = false
    
    /// Cached default output device ID
    private var defaultOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
    
    // MARK: - Initialization
    
    init() {
        // Cache the default output device
        defaultOutputDeviceID = getDefaultOutputDevice()
        
        // Load bundled macOS dictation sounds from SPM resource bundle
        if let url = Bundle.module.url(forResource: "begin_record", withExtension: "caf", subdirectory: "Sounds") {
            startSound = NSSound(contentsOf: url, byReference: false)
            logger.debug("Loaded start sound")
        } else {
            logger.warning("Could not load begin_record.caf")
        }
        
        if let url = Bundle.module.url(forResource: "end_record", withExtension: "caf", subdirectory: "Sounds") {
            endSound = NSSound(contentsOf: url, byReference: false)
            logger.debug("Loaded end sound")
        } else {
            logger.warning("Could not load end_record.caf")
        }
        
        if let url = Bundle.module.url(forResource: "dictation_error", withExtension: "caf", subdirectory: "Sounds") {
            errorSound = NSSound(contentsOf: url, byReference: false)
            logger.debug("Loaded error sound")
        } else {
            logger.warning("Could not load dictation_error.caf")
        }
    }
    
    // MARK: - Sound Playback
    
    /// Play sound when recording starts.
    func playStartSound() {
        startSound?.play()
    }
    
    /// Play sound when transcription succeeds.
    func playSuccessSound() {
        endSound?.play()
    }
    
    /// Play sound when transcription fails.
    func playErrorSound() {
        errorSound?.play()
    }
    
    /// Play sound when no transcription detected (empty).
    /// Uses system "Tink" sound for a subtle "nothing there" feel.
    func playEmptySound() {
        NSSound(named: "Tink")?.play()
    }
    
    // MARK: - Volume Ducking (using AudioDeviceDuck API)
    
    /// Duck other audio during recording using CoreAudio's AudioDeviceDuck.
    /// This lowers other audio by ~20dB while allowing our sounds to play at full volume.
    /// Call this when recording starts.
    func duckVolume() {
        guard !isVolumeDucked else { return }
        
        let status = AudioDeviceDuck(
            defaultOutputDeviceID,
            VolumeDucking.duckedLevel,
            nil,
            VolumeDucking.duckRampDuration
        )
        if status == noErr {
            isVolumeDucked = true
            logger.debug("Volume ducked")
        } else {
            logger.warning("AudioDeviceDuck failed with status \(status)")
        }
    }
    
    /// Restore audio volume after recording ends.
    /// Call this when recording stops (success, error, or cancel).
    func restoreVolume() {
        guard isVolumeDucked else { return }
        
        let status = AudioDeviceDuck(
            defaultOutputDeviceID,
            VolumeDucking.normalLevel,
            nil,
            VolumeDucking.restoreRampDuration
        )
        if status == noErr {
            isVolumeDucked = false
            logger.debug("Volume restored")
        } else {
            logger.warning("AudioDeviceDuck restore failed with status \(status)")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Get the default output audio device ID
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if status != noErr {
            logger.warning("Failed to get default output device: \(status)")
        }
        
        return deviceID
    }
}
