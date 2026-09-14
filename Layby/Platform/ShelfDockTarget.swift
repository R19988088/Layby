import AppKit

/// A display-local magnetic anchor, expressed in global screen coordinates.
struct ShelfDockTarget: Equatable {
    static let gap: CGFloat = 4
    static let releaseDistance: CGFloat = 28
    let displayID: UInt32
    let anchor: CGRect
    let visibleFrame: CGRect

    func frame(for size: CGSize) -> CGRect {
        let top = anchor.minY - Self.gap + ShelfLayout.shadowInset
        let size = CGSize(width: min(size.width, visibleFrame.width - 24),
                          height: min(size.height, top - visibleFrame.minY - 12))
        return CGRect(x: anchor.midX - size.width / 2, y: top - size.height,
                      width: size.width, height: size.height)
    }

    func captures(_ windowFrame: CGRect) -> Bool {
        let target = frame(for: windowFrame.size)
        return abs(windowFrame.midX - target.midX) <= max(80, anchor.width / 2 + 24)
            && abs(windowFrame.maxY - target.maxY) <= 52
    }

    /// Keep the physical display center even when a side Dock shifts the usable area.
    /// Without a notch, dock below the menu bar (or at the top when it is hidden).
    static func target(displayID: UInt32, frame: CGRect, visibleFrame: CGRect,
                       notch: CGRect?) -> ShelfDockTarget {
        let anchor = notch ?? CGRect(x: frame.midX, y: visibleFrame.maxY, width: 0, height: 0)
        return ShelfDockTarget(displayID: displayID, anchor: anchor, visibleFrame: visibleFrame)
    }

    @MainActor static func currentScreens() -> [ShelfDockTarget] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let notch = ShelfGeometry.notch(frame: screen.frame, topInset: screen.safeAreaInsets.top,
                left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
            return target(displayID: id.uint32Value, frame: screen.frame,
                          visibleFrame: screen.visibleFrame, notch: notch)
        }
    }
}
