import SwiftUI

/// State for waveform animation behavior.
enum WaveformState: Equatable {
    /// Recording - responsive to audio level (random bars)
    case recording
    /// Processing - sequential ripple wave (Apple-style loading)
    case processing
    /// Error - shake + flatline (something went wrong)
    case error
    /// Empty - gentle flatline (no transcription detected)
    case empty
    /// Success - quick fade (completed successfully)
    case success
}

/// Compact 4-bar waveform visualization for the notch UI.
///
/// Features:
/// - 4 vertical bars
/// - Recording: Random bar heights, responsive to audio
/// - Processing: Sequential ripple wave (Apple-style loading)
/// - Error: Shake + flatline
/// - Empty: Gentle flatline
/// - Success: Quick fade
/// - 60fps continuous animation using TimelineView
struct NotchWaveformView: View {
    
    /// Current audio level (0.0 to 1.0) from RecordingService.
    var audioLevel: Float
    
    /// Current waveform animation state.
    var state: WaveformState = .recording
    
    // MARK: - Constants
    
    private let barCount = 4
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 2
    private let totalHeight: CGFloat = 14
    
    // MARK: - State for Recording Mode
    
    /// Target bar scales that we interpolate towards (for recording mode).
    @State private var targetScales: [CGFloat] = [0.4, 0.5, 0.35, 0.45]
    
    /// Current interpolated bar scales (for recording mode).
    @State private var currentScales: [CGFloat] = [0.4, 0.5, 0.35, 0.45]
    
    /// Last time we updated the target scales.
    @State private var lastTargetUpdate: TimeInterval = 0
    
    // MARK: - State for Error/Empty/Success animations
    
    /// Horizontal shake offset for error state.
    @State private var shakeOffset: CGFloat = 0
    
    /// Scale multiplier for flatline/fade animations.
    @State private var flatlineProgress: CGFloat = 1.0
    
    /// Time when special animation started.
    @State private var animationStartTime: TimeInterval?
    
    // MARK: - Body
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(Color.white)
                        .frame(width: barWidth, height: barHeight(for: index, at: time))
                }
            }
            .frame(height: totalHeight)
            .offset(x: shakeOffset)
            .onChange(of: time) { _, newTime in
                updateAnimation(at: newTime)
            }
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }
    
    // MARK: - State Change Handling
    
    private func handleStateChange(from oldState: WaveformState, to newState: WaveformState) {
        // Reset animation start time for special states
        if newState == .error || newState == .empty || newState == .success {
            animationStartTime = Date().timeIntervalSinceReferenceDate
            flatlineProgress = 1.0
            shakeOffset = 0
        }
    }
    
    // MARK: - Animation Update
    
    private func updateAnimation(at time: TimeInterval) {
        switch state {
        case .recording:
            updateRecordingAnimation(at: time)
        case .processing:
            // Processing uses direct calculation in barHeight, no state update needed
            break
        case .error:
            updateErrorAnimation(at: time)
        case .empty:
            updateEmptyAnimation(at: time)
        case .success:
            updateSuccessAnimation(at: time)
        }
    }
    
    // MARK: - Bar Height Calculation
    
    private func barHeight(for index: Int, at time: TimeInterval) -> CGFloat {
        switch state {
        case .recording:
            return totalHeight * currentScales[index]
        case .processing:
            return processingHeight(for: index, at: time)
        case .error, .empty:
            // Flatline effect - all bars go to minimum, multiplied by flatlineProgress
            let minHeight = totalHeight * 0.15
            let currentHeight = totalHeight * currentScales[index]
            let flatlinedHeight = minHeight + (currentHeight - minHeight) * flatlineProgress
            return max(minHeight, flatlinedHeight)
        case .success:
            // Fade out - bars shrink based on flatlineProgress
            return totalHeight * currentScales[index] * flatlineProgress
        }
    }
    
    /// Processing mode: Sequential ripple wave (Apple-style).
    private func processingHeight(for index: Int, at time: TimeInterval) -> CGFloat {
        // Phase offset creates full wave pattern across bars
        let phase = Double(index) * 1.5
        // ~2 second full cycle (slowed down)
        let scale = 0.45 + 0.4 * sin(time * 3.0 + phase)
        return totalHeight * scale
    }
    
    // MARK: - Recording Animation
    
    private func updateRecordingAnimation(at time: TimeInterval) {
        let updateInterval: TimeInterval = audioLevel > 0.15 ? 0.15 : 0.3
        
        if time - lastTargetUpdate > updateInterval {
            lastTargetUpdate = time
            generateNewTargets()
        }
        
        let interpolationSpeed: CGFloat = 0.15
        for i in 0..<barCount {
            currentScales[i] += (targetScales[i] - currentScales[i]) * interpolationSpeed
        }
    }
    
    private func generateNewTargets() {
        let minScale: CGFloat = 0.35
        let idleMax: CGFloat = 0.45
        let activeMax: CGFloat = min(1.0, 0.5 + CGFloat(audioLevel) * 1.0)
        
        let blendFactor = CGFloat(min(1, audioLevel / 0.3))
        let blendedMax = idleMax + (activeMax - idleMax) * blendFactor
        
        targetScales = (0..<barCount).map { _ in
            CGFloat.random(in: minScale...blendedMax)
        }
    }
    
    // MARK: - Error Animation (Shake + Flatline)
    
    private func updateErrorAnimation(at time: TimeInterval) {
        guard let startTime = animationStartTime else { return }
        let elapsed = time - startTime
        
        // Phase 1: Shake (0 - 0.4 seconds)
        if elapsed < 0.4 {
            let shakeFrequency: Double = 25
            let shakeMagnitude: CGFloat = 6
            let decay = 1.0 - (elapsed / 0.4)
            shakeOffset = sin(elapsed * shakeFrequency) * shakeMagnitude * decay
        } else {
            shakeOffset = 0
        }
        
        // Phase 2: Flatline (0.2 - 0.6 seconds)
        if elapsed > 0.2 {
            let flatlineElapsed = elapsed - 0.2
            let flatlineDuration: Double = 0.4
            flatlineProgress = max(0, 1.0 - (flatlineElapsed / flatlineDuration))
        }
    }
    
    // MARK: - Empty Animation (Gentle Flatline)
    
    private func updateEmptyAnimation(at time: TimeInterval) {
        guard let startTime = animationStartTime else { return }
        let elapsed = time - startTime
        
        // Gentle flatline over 0.5 seconds
        let flatlineDuration: Double = 0.5
        flatlineProgress = max(0, 1.0 - (elapsed / flatlineDuration))
    }
    
    // MARK: - Success Animation (Quick Fade)
    
    private func updateSuccessAnimation(at time: TimeInterval) {
        guard let startTime = animationStartTime else { return }
        let elapsed = time - startTime
        
        // Quick fade over 0.3 seconds
        let fadeDuration: Double = 0.3
        flatlineProgress = max(0, 1.0 - (elapsed / fadeDuration))
    }
}

// MARK: - Preview

#Preview("Recording - Silent") {
    NotchWaveformView(audioLevel: 0, state: .recording)
        .padding(12)
        .background(Color.black)
        .padding(40)
}

#Preview("Recording - Speaking") {
    NotchWaveformView(audioLevel: 0.6, state: .recording)
        .padding(12)
        .background(Color.black)
        .padding(40)
}

#Preview("Processing") {
    NotchWaveformView(audioLevel: 0, state: .processing)
        .padding(12)
        .background(Color.black)
        .padding(40)
}

#Preview("Error") {
    NotchWaveformView(audioLevel: 0, state: .error)
        .padding(12)
        .background(Color.black)
        .padding(40)
}

#Preview("Empty") {
    NotchWaveformView(audioLevel: 0, state: .empty)
        .padding(12)
        .background(Color.black)
        .padding(40)
}

#Preview("Success") {
    NotchWaveformView(audioLevel: 0, state: .success)
        .padding(12)
        .background(Color.black)
        .padding(40)
}
