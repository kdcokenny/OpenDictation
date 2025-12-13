import SwiftUI

/// Custom notch shape with ear curves built into the path geometry.
///
/// Uses Boring Notch corner radii values:
/// - Collapsed: top 6, bottom 14
/// - Expanded: top 6, bottom 24
///
/// Only animates bottomCornerRadius to avoid corner "popping" artifacts.
struct NotchShape: Shape {
    
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    
    init(
        topCornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat = 14
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }
    
    // MARK: - Animatable (mew-notch pattern: only animate bottomRadius)
    
    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }
    
    // MARK: - Shape (mew-notch path exactly)
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let topRadius = topCornerRadius
        let bottomRadius = bottomCornerRadius
        
        // Start at top-left corner
        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )
        
        // LEFT EAR - curves down and to the right
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.minY + topRadius
            ),
            control: CGPoint(
                x: rect.minX + topRadius,
                y: rect.minY
            )
        )
        
        // Left edge - go down to bottom-left corner
        path.addLine(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.maxY - bottomRadius
            )
        )
        
        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topRadius + bottomRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topRadius,
                y: rect.maxY
            )
        )
        
        // Bottom edge
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius - bottomRadius,
                y: rect.maxY
            )
        )
        
        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.maxY - bottomRadius
            ),
            control: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.maxY
            )
        )
        
        // Right edge - go up to top-right
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.minY + topRadius
            )
        )
        
        // RIGHT EAR - curves up and to the right
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.minY
            )
        )
        
        // Top edge - close the path back to start
        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )
        
        return path
    }
}

// MARK: - Preview

#Preview("NotchShape - Collapsed") {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .fill(Color.black)
        .frame(width: 192, height: 37)  // 180 + 12 (6*2 for ears)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("NotchShape - Expanded") {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 24)
        .fill(Color.black)
        .frame(width: 262, height: 37)  // 180 + 12 + 70 (35*2 expansions)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
