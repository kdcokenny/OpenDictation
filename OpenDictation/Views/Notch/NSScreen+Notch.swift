import AppKit

/// Extension to detect hardware notch on MacBook screens.
/// Uses public APIs (safeAreaInsets, auxiliaryTopLeftArea/Right) per NotchDrop pattern.
extension NSScreen {

    /// The size of the hardware notch on this screen.
    /// Returns `.zero` if there is no notch (e.g., external display or older MacBook).
    ///
    /// Source: Lakr233/NotchDrop Ext+NSScreen.swift
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }

        let notchHeight = safeAreaInsets.top + 0.25  // + 0.25 accounts for the rounded corners
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        // Extra guard from NotchDrop to ensure we have valid padding values
        guard leftPadding > 0, rightPadding > 0 else { return .zero }

        let notchWidth = frame.width - leftPadding - rightPadding

        return CGSize(width: notchWidth, height: notchHeight)
    }

    /// Whether this screen has a hardware notch.
    var hasNotch: Bool {
        notchSize != .zero
    }

    /// The frame of the notch area in screen coordinates.
    /// Returns `.zero` if there is no notch.
    var notchFrame: CGRect {
        guard hasNotch else { return .zero }

        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let notchY = frame.maxY - safeAreaInsets.top

        return CGRect(
            x: frame.minX + leftPadding,
            y: notchY,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    /// Returns the screen with a hardware notch, or nil if none exists.
    /// Typically this is the built-in display on notch MacBooks.
    static var screenWithNotch: NSScreen? {
        screens.first { $0.hasNotch }
    }
}
