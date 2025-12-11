import SwiftUI

/// Visual state for the HUD view, derived from DictationState.
enum HUDVisualState: Equatable {
    case recording
    case processing
    case success
    case copiedToClipboard
    case error
    case empty
}

/// Observable state for the HUD view.
final class HUDState: ObservableObject {
    @Published var visualState: HUDVisualState = .recording
    @Published var isVisible: Bool = false
    
    /// Current audio level (0.0 to 1.0) from RecordingService for waveform visualization.
    @Published var audioLevel: Float = 0
}

/// The SwiftUI view displayed inside the dictation overlay panel.
/// Floating pill with glass material effect and waveform visualization.
struct DictationHUDView: View {
    @ObservedObject var state: HUDState
    
    private let pillWidth: CGFloat = 72
    private let pillHeight: CGFloat = 26
    private let shakePadding: CGFloat = 10  // Extra space for shake animation
    
    // Shake animation state
    @State private var shakeOffset: CGFloat = 0
    
    /// Total width including shake padding (for panel sizing)
    static let totalWidth: CGFloat = 72 + 10 * 2  // pillWidth + shakePadding * 2
    static let totalHeight: CGFloat = 26
    
    var body: some View {
        ZStack {
            switch state.visualState {
            case .recording, .processing:
                WaveformView(
                    isProcessing: state.visualState == .processing,
                    audioLevel: state.audioLevel
                )
                
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
            case .copiedToClipboard:
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
            case .empty:
                Image(systemName: "waveform.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(.ultraThinMaterial, in: Capsule())
        // No overlay - icon alone conveys state
        .offset(x: shakeOffset)
        .padding(.horizontal, shakePadding)  // Room for shake animation
        .scaleEffect(state.isVisible ? 1.0 : 0.95)
        .opacity(state.isVisible ? 1.0 : 0.0)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: state.isVisible)
        .onChange(of: state.visualState) { _, newState in
            if newState == .empty || newState == .error {
                performShakeAnimation()
            }
        }
    }
    
    // MARK: - Shake Animation
    
    /// Performs a horizontal shake animation using macOS-native dampening pattern.
    /// Pattern: [-5, 5, -2.5, 2.5, 0] - starts strong, dampens to center
    private func performShakeAnimation() {
        // Dampening shake values (like macOS login window rejection)
        let shakeValues: [CGFloat] = [-5, 5, -2.5, 2.5, 0]
        let totalDuration: Double = 0.3
        let stepDuration = totalDuration / Double(shakeValues.count)
        
        for (index, value) in shakeValues.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(index)) {
                withAnimation(.linear(duration: stepDuration)) {
                    shakeOffset = value
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        Text("Recording")
            .font(.caption)
        DictationHUDView(state: {
            let s = HUDState()
            s.visualState = .recording
            s.isVisible = true
            return s
        }())
        
        Text("Processing")
            .font(.caption)
        DictationHUDView(state: {
            let s = HUDState()
            s.visualState = .processing
            s.isVisible = true
            return s
        }())
        
        Text("Error")
            .font(.caption)
        DictationHUDView(state: {
            let s = HUDState()
            s.visualState = .error
            s.isVisible = true
            return s
        }())
        
        Text("Empty (will shake)")
            .font(.caption)
        DictationHUDView(state: {
            let s = HUDState()
            s.visualState = .empty
            s.isVisible = true
            return s
        }())
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
