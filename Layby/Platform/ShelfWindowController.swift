import AppKit
import SwiftUI

@MainActor
final class ShelfPanel: NSPanel {
    var onHide: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onCopy: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { onHide?() }
    override func performClose(_ sender: Any?) { close() }
    override func cancelOperation(_ sender: Any?) { onHide?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": onSelectAll?(); return true
            case "c": onCopy?(); return true
            case "w": onHide?(); return true
            default: break
            }
        }
        if event.keyCode == 53 { onHide?(); return true }
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// A transparent window surface with an explicit rounded shadow, independent of key state.
@MainActor
final class ShelfSurfaceView: NSView {
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusRingType = .none
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: ShelfLayout.shadowInset, dy: ShelfLayout.shadowInset),
                                  cornerWidth: ShelfLayout.cornerRadius, cornerHeight: ShelfLayout.cornerRadius, transform: nil)
    }
}

@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel
    let destination: DropDestinationView
    private let store: ShelfStore
    private let glass: NSGlassEffectView
    private var accessibilityObserver: NSObjectProtocol?
    var onHide: (() -> Void)?
    var onBeginMoving: (() -> Void)?

    init(store: ShelfStore) {
        self.store = store
        panel = ShelfPanel(contentRect: CGRect(origin: .zero, size: ShelfLayout.windowSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Layby 文件停放区"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // WindowServer's shadow can outline the rectangular backing surface when it becomes key.
        // Draw a rounded shadow in our transparent surface instead.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        destination = DropDestinationView(store: store)
        glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = ShelfLayout.cornerRadius
        glass.wantsLayer = true
        glass.layer?.cornerRadius = ShelfLayout.cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.focusRingType = .none
        glass.contentView = destination
        let surface = ShelfSurfaceView(frame: CGRect(origin: .zero, size: ShelfLayout.windowSize))
        panel.contentView = surface
        glass.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: ShelfLayout.shadowInset),
            glass.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -ShelfLayout.shadowInset),
            glass.topAnchor.constraint(equalTo: surface.topAnchor, constant: ShelfLayout.shadowInset),
            glass.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -ShelfLayout.shadowInset)
        ])
        panel.onHide = { [weak self] in self?.hide() }
        panel.onSelectAll = { [weak store] in store?.selection = Set(store?.readyItems.map(\.id) ?? []) }
        panel.onDelete = { [weak store] in if let store { store.remove(store.selection) } }
        panel.onCopy = { [weak store] in store?.copySelection() }
        installShelfContent()
        updateAccessibility()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAccessibility() }
            }
    }

    private func installShelfContent() {
        guard destination.subviews.isEmpty else { return }
        let host = NSHostingView(rootView: ShelfView(store: store,
            hide: { [weak self] in self?.hide() }, beginMoving: { [weak self] in self?.onBeginMoving?() },
            presentationChanged: { [weak self] in self?.resizeForPresentation() }))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.focusRingType = .none
        destination.focusRingType = .none
        destination.addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: destination.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: destination.trailingAnchor), host.topAnchor.constraint(equalTo: destination.topAnchor),
            host.bottomAnchor.constraint(equalTo: destination.bottomAnchor)])
    }

    private func resizeForPresentation() {
        guard panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        let frame = ShelfGeometry.resizedFrame(panel.frame, size: ShelfLayout.windowSize(for: store.presentation),
                                               in: screen.visibleFrame.insetBy(dx: 12, dy: 12))
        guard frame != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func show(near point: CGPoint, focus: Bool, notchScreen: NSScreen? = nil) {
        installShelfContent()
        store.refreshReferences()
        let screen = notchScreen ?? NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let screen {
            let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            var frame = ShelfGeometry.frame(size: ShelfLayout.windowSize(for: store.presentation), near: point, in: bounds)
            if notchScreen != nil {
                frame.origin.x = screen.frame.midX - frame.width / 2
                frame.origin.y = screen.frame.maxY - screen.safeAreaInsets.top - frame.height - 12
                frame.origin.y = max(bounds.minY, frame.origin.y)
            }
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
        if focus { panel.makeKey() }
    }

    func hide() {
        panel.orderOut(nil)
        panel.makeFirstResponder(nil)
        store.clear()
        // Hidden SwiftUI rows can retain item snapshots and their file leases. Tear them
        // down now; the next presentation builds fresh content from the empty store.
        destination.subviews.forEach { $0.removeFromSuperview() }
        onHide?()
    }
    func stop() {
        hide()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    private func updateAccessibility() {
        destination.wantsLayer = true
        destination.layer?.backgroundColor = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        destination.layer?.cornerRadius = ShelfLayout.cornerRadius
    }
}
