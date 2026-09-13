import AppKit

/// A display-local magnetic anchor, expressed in global screen coordinates.
struct ShelfDockTarget: Equatable {
    static let gap: CGFloat = 4
    static let releaseDistance: CGFloat = 28
    let displayID: UInt32
    let notch: CGRect
    let visibleFrame: CGRect

    func frame(for size: CGSize) -> CGRect {
        let top = notch.minY - Self.gap + ShelfLayout.shadowInset
        let size = CGSize(width: min(size.width, visibleFrame.width - 24),
                          height: min(size.height, top - visibleFrame.minY - 12))
        return CGRect(x: notch.midX - size.width / 2, y: top - size.height,
                      width: size.width, height: size.height)
    }

    func captures(_ windowFrame: CGRect) -> Bool {
        let target = frame(for: windowFrame.size)
        return abs(windowFrame.midX - target.midX) <= max(80, notch.width / 2 + 24)
            && abs(windowFrame.maxY - target.maxY) <= 52
    }

    @MainActor static func currentScreens() -> [ShelfDockTarget] {
        NSScreen.screens.compactMap { screen in
            guard let notch = ShelfGeometry.notch(frame: screen.frame, topInset: screen.safeAreaInsets.top,
                left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea),
                  let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ShelfDockTarget(displayID: id.uint32Value, notch: notch, visibleFrame: screen.visibleFrame)
        }
    }
}
