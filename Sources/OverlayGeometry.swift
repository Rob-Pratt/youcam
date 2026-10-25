import Foundation

enum CameraShape: String, CaseIterable, Sendable {
    case circle
    case square
    case rectangle

    var title: String {
        switch self {
        case .circle: "Circle"
        case .square: "Square"
        case .rectangle: "Rectangle (16:9)"
        }
    }

    var aspectRatio: CGFloat { self == .rectangle ? 16.0 / 9.0 : 1 }
}

enum OverlayGeometry {
    static let minimumWidth: CGFloat = 120
    static let maximumWidth: CGFloat = 960

    static func size(width: CGFloat, shape: CameraShape, within screen: CGRect) -> CGSize {
        let limit = min(maximumWidth, screen.width, screen.height * shape.aspectRatio)
        let safeWidth = width.isFinite ? width : 280
        let width = min(max(safeWidth, minimumWidth), limit)
        return CGSize(width: width, height: width / shape.aspectRatio)
    }

    static func constrain(_ frame: CGRect, to screen: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(screen.minX, min(frame.minX, screen.maxX - frame.width))
        frame.origin.y = max(screen.minY, min(frame.minY, screen.maxY - frame.height))
        return frame
    }

    // Keep the top-left corner still when changing size or aspect ratio.
    static func resized(_ frame: CGRect, width: CGFloat, shape: CameraShape, within screen: CGRect) -> CGRect {
        let size = size(width: width, shape: shape, within: screen)
        return constrain(CGRect(x: frame.minX, y: frame.maxY - size.height,
                                width: size.width, height: size.height), to: screen)
    }

    static func initial(width: CGFloat, shape: CameraShape, within screen: CGRect) -> CGRect {
        let size = size(width: width, shape: shape, within: screen)
        return constrain(CGRect(x: screen.maxX - size.width - 32, y: screen.minY + 32,
                                width: size.width, height: size.height), to: screen)
    }
}
