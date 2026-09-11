import Foundation
import CoreGraphics

enum ShelfGeometry {
    /// Expand around the existing top center; keep the full window inside its display.
    static func resizedFrame(_ frame: CGRect, size: CGSize, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        return CGRect(x: min(max(frame.midX - size.width / 2, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.maxY - size.height, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func frame(size: CGSize, near point: CGPoint, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        var x = point.x + 28
        var y = point.y - size.height - 28
        if x + size.width > bounds.maxX { x = point.x - size.width - 28 }
        if y < bounds.minY { y = point.y + 28 }
        return CGRect(x: min(max(x, bounds.minX), bounds.maxX - size.width),
                      y: min(max(y, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func notch(frame: CGRect, topInset: CGFloat, left: CGRect?, right: CGRect?) -> CGRect? {
        guard topInset > 0, let left, let right, !left.isEmpty, !right.isEmpty,
              left.maxX < right.minX, left.minX >= frame.minX, right.maxX <= frame.maxX else { return nil }
        return CGRect(x: left.maxX, y: frame.maxY - topInset,
                      width: right.minX - left.maxX, height: topInset)
    }
}
