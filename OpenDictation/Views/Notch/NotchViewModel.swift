import SwiftUI
import Combine

/// Visual state for the notch dictation view.
enum NotchVisualState: Equatable {
    case recording
    case processing
    case success
    case copiedToClipboard
    case error
    case empty
}

/// Observable state for the notch dictation panel.
///
/// Follows Apple's Dynamic Island pattern:
/// - Shape and content are separate concerns
/// - Hardware notch size is the raw value, no computed padding
/// - Animations triggered via withAnimation blocks
@MainActor
final class NotchViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current visual state of the dictation UI.
    @Published var visualState: NotchVisualState = .recording
    
    /// Whether the notch panel is expanded (visible).
    @Published var isExpanded: Bool = false
    
    /// Current audio level (0.0 to 1.0) from RecordingService for waveform visualization.
    @Published var audioLevel: Float = 0
    
    // MARK: - Hardware Notch Size
    
    /// The raw hardware notch size from the screen (no padding added).
    private(set) var hardwareNotchSize: CGSize = .zero
    
    // MARK: - Constants (Boring Notch values)
    
    /// Expansion width on each side of the notch.
    /// Based on content needs: 16px icon + 6px ear clearance + padding ≈ 35px
    static let expansionWidth: CGFloat = 35
    
    /// Corner radius values for collapsed state.
    static let collapsedCornerRadius: (top: CGFloat, bottom: CGFloat) = (top: 6, bottom: 14)
    
    /// Corner radius values for expanded state.
    static let expandedCornerRadius: (top: CGFloat, bottom: CGFloat) = (top: 6, bottom: 24)
    
    // MARK: - Computed Properties
    
    /// Whether the recording indicator should pulse.
    var isRecording: Bool {
        visualState == .recording
    }
    
    /// Whether the processing indicator should breathe.
    var isProcessing: Bool {
        visualState == .processing
    }
    
    /// Total width of the notch shape (hardware notch + ears + expansions if expanded).
    var notchShapeWidth: CGFloat {
        let earWidth = Self.collapsedCornerRadius.top * 2  // Space for both ear curves
        let expansionWidth = isExpanded ? Self.expansionWidth * 2 : 0
        return hardwareNotchSize.width + earWidth + expansionWidth
    }
    
    // MARK: - Initialization
    
    /// Configure with the hardware notch size from the screen.
    func configure(hardwareNotchSize: CGSize) {
        self.hardwareNotchSize = hardwareNotchSize
    }
    
    // MARK: - Methods
    
    /// Expands the notch panel with animation (Apple Dynamic Island pattern).
    func expand() {
        // Shape expands with bouncy spring
        withAnimation(.spring(.bouncy(duration: 0.4, extraBounce: 0.1))) {
            self.isExpanded = true
        }
    }
    
    /// Collapses the notch panel with animation (Apple pattern: fast dismissal).
    func collapse() {
        // Content and shape collapse together, slightly faster than expand
        withAnimation(.easeOut(duration: 0.3)) {
            self.isExpanded = false
        }
    }
    
    /// Updates the visual state.
    func setVisualState(_ state: NotchVisualState) {
        visualState = state
    }
    
    /// Updates the audio level for waveform.
    func setAudioLevel(_ level: Float) {
        audioLevel = level
    }
}
