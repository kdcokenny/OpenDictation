import SwiftUI

/// Main SwiftUI view for the notch-based dictation UI.
///
/// Follows Apple's Dynamic Island / NotchDrop pattern:
/// - Shape layer (Layer 0): Black notch shape with explicit frame, always visible
/// - Content layer (Layer 1): Content overlay with transition, only when expanded
/// - Shape and content are separate concerns, animate independently
///
/// Layout (expanded recording state):
/// ```
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ [Mic Icon]      ████████ HARDWARE NOTCH ████████         [Waveform]     │
/// │   16px                    ~180px                            16px        │
/// │   +6px padding                                              +6px padding│
/// └─────────────────────────────────────────────────────────────────────────┘
///     35px                                                        35px
/// ```
struct NotchDictationView: View {

    @ObservedObject var viewModel: NotchViewModel

    // MARK: - Constants

    /// Icon size for SF Symbols (matches waveform totalHeight).
    private let iconSize: CGFloat = 14

    /// Shake animation offset.
    @State private var shakeOffset: CGFloat = 0

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Layer 0: Shape (always visible, explicit size)
            notchShape
            
            // Layer 1: Content (only when expanded, overlays shape)
            notchContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(x: shakeOffset)
        .onChange(of: viewModel.visualState) { _, newState in
            if newState == .empty || newState == .error {
                performShakeAnimation()
            }
        }
    }

    // MARK: - Layer 0: Notch Shape (Pure Chrome)
    
    /// The black notch shape with ears. Has explicit frame based on expansion state.
    /// Separate from content - just the visual chrome.
    private var notchShape: some View {
        Rectangle()
            .fill(Color.black)
            .mask {
                NotchShape(
                    topCornerRadius: viewModel.isExpanded ? 6 : 6,
                    bottomCornerRadius: viewModel.isExpanded ? 24 : 14
                )
            }
            .frame(
                width: viewModel.notchShapeWidth,
                height: viewModel.hardwareNotchSize.height
            )
    }

    // MARK: - Layer 1: Notch Content (Overlay)
    
    /// Content that appears on top of the shape when expanded.
    /// Each content piece manages its own edge padding.
    @ViewBuilder
    private var notchContent: some View {
        if viewModel.isExpanded {
            HStack(spacing: 0) {
                // Left content - manages its own edge padding
                leftContent
                    .padding(.leading, 6)  // Clear left ear
                    .frame(
                        width: NotchViewModel.expansionWidth,
                        height: viewModel.hardwareNotchSize.height,
                        alignment: .center
                    )
                
                // Center spacer - exactly hardware notch width (no padding)
                Spacer()
                    .frame(width: viewModel.hardwareNotchSize.width)
                
                // Right content - manages its own edge padding
                rightContent
                    .padding(.trailing, 6)  // Clear right ear
                    .frame(
                        width: NotchViewModel.expansionWidth,
                        height: viewModel.hardwareNotchSize.height,
                        alignment: .center
                    )
            }
            .frame(height: viewModel.hardwareNotchSize.height, alignment: .center)
            .transition(
                .scale(scale: 0.6, anchor: .top)
                .combined(with: .opacity)
            )
        }
    }

    // MARK: - Left Content (Context-Aware Icon)
    
    /// Icon indicating dictation context - uses ContextCategory SF symbols.
    private var leftContent: some View {
        Image(systemName: viewModel.currentContext.category.sfSymbol)
            .font(.system(size: iconSize, weight: .regular))
            .foregroundStyle(.white)
    }

    // MARK: - Right Content (Waveform)
    
    /// Waveform visualization.
    private var rightContent: some View {
        NotchWaveformView(
            audioLevel: viewModel.audioLevel,
            state: waveformState
        )
    }
    
    /// Map visual state to waveform animation state.
    private var waveformState: WaveformState {
        switch viewModel.visualState {
        case .recording: .recording
        case .processing: .processing
        case .success, .copiedToClipboard: .success
        case .error: .error
        case .empty: .empty
        }
    }

    // MARK: - Shake Animation

    /// Performs a horizontal shake animation (3 cycles, dampening).
    private func performShakeAnimation() {
        let shakeValues: [CGFloat] = [-8, 8, -6, 6, -4, 4, 0]
        let totalDuration: Double = 0.4
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

// MARK: - Preview

#Preview("Recording - Expanded") {
    let vm = NotchViewModel()
    vm.configure(hardwareNotchSize: CGSize(width: 180, height: 37))
    vm.isExpanded = true
    vm.visualState = .recording
    vm.audioLevel = 0.4

    return NotchDictationView(viewModel: vm)
        .frame(width: 500, height: 60)
        .background(Color.gray.opacity(0.3))
}

#Preview("Processing - Expanded") {
    let vm = NotchViewModel()
    vm.configure(hardwareNotchSize: CGSize(width: 180, height: 37))
    vm.isExpanded = true
    vm.visualState = .processing

    return NotchDictationView(viewModel: vm)
        .frame(width: 500, height: 60)
        .background(Color.gray.opacity(0.3))
}

#Preview("Collapsed") {
    let vm = NotchViewModel()
    vm.configure(hardwareNotchSize: CGSize(width: 180, height: 37))
    vm.isExpanded = false
    vm.visualState = .recording

    return NotchDictationView(viewModel: vm)
        .frame(width: 500, height: 60)
        .background(Color.gray.opacity(0.3))
}
