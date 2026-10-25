import Foundation

// Geometry uses AppKit's global coordinates (origin at the bottom left).
enum RecordingAreaCorner: String, CaseIterable {
    case topLeft = "Top left", topRight = "Top right"
    case bottomLeft = "Bottom left", bottomRight = "Bottom right"

    private var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    private var isTop: Bool { self == .topLeft || self == .topRight }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.maxY : rect.minY)
    }

    func resized(_ rect: CGRect, to point: CGPoint, within screen: CGRect, scale: CGFloat) -> CGRect {
        // Keep the opposite corner fixed, stay on this display, and retain the
        // picker's 40-point minimum size. Align the moving edges to screen pixels.
        let x = screen.minX + ((point.x - screen.minX) * scale).rounded() / scale
        let y = screen.minY + ((point.y - screen.minY) * scale).rounded() / scale
        let minX = isLeft ? max(screen.minX, min(rect.maxX - 40, x)) : rect.minX
        let maxX = isLeft ? rect.maxX : min(screen.maxX, max(rect.minX + 40, x))
        let minY = isTop ? rect.minY : max(screen.minY, min(rect.maxY - 40, y))
        let maxY = isTop ? min(screen.maxY, max(rect.minY + 40, y)) : rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
