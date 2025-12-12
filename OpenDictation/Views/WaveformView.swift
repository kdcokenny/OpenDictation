import SwiftUI

/// Animated waveform visualization with 10 vertical bars.
///
/// Uses `TimelineView(.animation)` for smooth 60fps animation synced to display refresh.
///
/// Supports two animation modes:
/// - **Recording**: Real audio-reactive bars driven by microphone input
/// - **Processing**: Traveling sine wave (indicates "thinking")
struct WaveformView: View {
    
    /// Whether the view is in processing mode (vs recording mode)
    var isProcessing: Bool
    
    /// Current audio level (0.0 to 1.0) from RecordingService. Used during recording.
    var audioLevel: Float
    
    // MARK: - Constants
    
    private let barCount = 10
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 16
    
    // Wave animation parameters (same style for recording & processing)
    private let waveSpeed: Double = 2.0
    private let phaseSpread: Double = 0.5  // Phase difference between adjacent bars
    private let idleAmplitude: Float = 0.08  // Subtle movement when silent
    
    // MARK: - Body
    
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(.primary)
                        .frame(width: barWidth, height: barHeight(for: index, time: time))
                }
            }
        }
    }
    
    // MARK: - Animation
    
    private func barHeight(for index: Int, time: Double) -> CGFloat {
        // Traveling sine wave (same pattern for recording & processing)
        let wavePhase = time * waveSpeed + Double(index) * phaseSpread
        let waveValue = (sin(wavePhase) + 1) / 2  // 0 to 1
        
        // Amplitude: use audioLevel for recording, full for processing
        let amplitude = isProcessing ? Float(1.0) : max(audioLevel, idleAmplitude)
        
        // Wave modulates bar height based on amplitude
        let barLevel = Float(waveValue) * amplitude
        
        return minHeight + (maxHeight - minHeight) * CGFloat(barLevel)
    }
}

// MARK: - Preview

#Preview("Recording (Low)") {
    WaveformView(isProcessing: false, audioLevel: 0.2)
        .padding(20)
        .background(.regularMaterial, in: Capsule())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Recording (High)") {
    WaveformView(isProcessing: false, audioLevel: 0.8)
        .padding(20)
        .background(.regularMaterial, in: Capsule())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Processing") {
    WaveformView(isProcessing: true, audioLevel: 0)
        .padding(20)
        .background(.regularMaterial, in: Capsule())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
