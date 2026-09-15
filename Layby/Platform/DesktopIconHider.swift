import AppKit
import CoreGraphics

@MainActor
final class DesktopIconHider {
    private var windows: [NSWindow] = []

    func start() { refresh() }

    func refresh() {
        stop()
        windows = NSScreen.screens.map { screen in
            let window = DesktopOverlayWindow(contentRect: CGRect(origin: .zero, size: screen.frame.size),
                styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = DesktopWallpaperView(screen: screen)
            window.orderFrontRegardless()
            return window
        }
    }

    func stop() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private final class DesktopOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DesktopWallpaperView: NSView {
    init(screen: NSScreen) {
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        let workspace = NSWorkspace.shared
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        layer?.backgroundColor = (options[.fillColor] as? NSColor ?? .black).cgColor
        layer?.contents = workspace.desktopImageURL(for: screen).flatMap(NSImage.init(contentsOf:))
        layer?.contentsGravity = options[.allowClipping] as? Bool == false ? .resizeAspect : .resizeAspectFill
        layer?.contentsScale = screen.backingScaleFactor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
