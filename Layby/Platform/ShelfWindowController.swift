import AppKit
import QuartzCore
import Quartz
import SwiftUI

@MainActor
final class ShelfPanel: NSPanel {
    var onHide: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onCopy: (() -> Void)?
    var onQuickLook: (() -> Bool)?
    var onNavigate: ((ShelfNavigationDirection) -> Bool)?
    var dismissQuickLook: (() -> Bool)?
    weak var quickLook: ShelfQuickLookController?
    weak var selectionBackground: ShelfSelectionBackgroundView?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { onHide?() }
    override func performClose(_ sender: Any?) { close() }
    override func cancelOperation(_ sender: Any?) {
        if dismissQuickLook?() != true { onHide?() }
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLook?.hasItems == true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook?.beginControl(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook?.endControl(panel) }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { selectionBackground?.handleMouseDown(event) }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if handleQuickLookKey(event) || handleNavigationKey(event) { return }
        super.keyDown(with: event)
    }

    func handleQuickLookKey(_ event: NSEvent) -> Bool {
        guard ShelfQuickLookController.isToggleKey(event) else { return false }
        // Holding Space must not repeatedly open and close the panel.
        return event.isARepeat || onQuickLook?() == true
    }

    static func navigationDirection(for event: NSEvent) -> ShelfNavigationDirection? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }

    func handleNavigationKey(_ event: NSEvent) -> Bool {
        guard let direction = Self.navigationDirection(for: event) else { return false }
        return onNavigate?(direction) ?? false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleQuickLookKey(event) || handleNavigationKey(event) { return true }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": onSelectAll?(); return true
            case "c": onCopy?(); return true
            case "w": onHide?(); return true
            default: break
            }
        }
        if event.keyCode == 53 { cancelOperation(nil); return true }
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// A transparent window surface with an explicit rounded shadow, independent of key state.
@MainActor
final class ShelfSurfaceView: NSView {
    private static let appearanceAnimationKey = "layby.appearance"
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: ShelfLayout.shadowInset, dy: ShelfLayout.shadowInset),
                                  cornerWidth: ShelfLayout.cornerRadius, cornerHeight: ShelfLayout.cornerRadius, transform: nil)
        CATransaction.commit()
    }

    func animateAppearance(reduceMotion: Bool) {
        stopAppearanceAnimation()
        guard !reduceMotion, let layer else { return }

        // Animate the presentation layer only: layout and the native drop target already
        // occupy their final bounds. Compensate for AppKit's layer anchor without moving it.
        let center = CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x),
                             y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
        // Uniform scaling preserves the window's shape; one overshoot settles directly to 100%.
        let scales: [CGFloat] = [0.38, 1.06, 1]
        let scaleAnimation = CAKeyframeAnimation(keyPath: "transform")
        scaleAnimation.values = scales.map { scale in
            var transform = CATransform3DMakeScale(scale, scale, 1)
            transform.m41 = center.x * (1 - scale)
            transform.m42 = center.y * (1 - scale)
            return NSValue(caTransform3D: transform)
        }
        // About 280 ms to grow visibly from a small surface, then a single 140 ms settle.
        scaleAnimation.keyTimes = [0, 0.67, 1]
        scaleAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        scaleAnimation.duration = 0.42

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.06
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards

        let appearance = CAAnimationGroup()
        appearance.animations = [scaleAnimation, fade]
        appearance.duration = scaleAnimation.duration
        layer.add(appearance, forKey: Self.appearanceAnimationKey)
    }

    func stopAppearanceAnimation() {
        // Model-layer geometry and opacity never change, so interruption restores them immediately.
        layer?.removeAnimation(forKey: Self.appearanceAnimationKey)
    }
}

@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel
    let destination: DropDestinationView
    private let store: ShelfStore
    private let glass: NSGlassEffectView
    private let surface: ShelfSurfaceView
    private let quickLook: ShelfQuickLookController
    private var accessibilityObserver: NSObjectProtocol?
    var onHide: (() -> Void)?
    var onBeginMoving: (() -> Void)?

    init(store: ShelfStore) {
        self.store = store
        panel = ShelfPanel(contentRect: CGRect(origin: .zero, size: ShelfLayout.windowSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        quickLook = ShelfQuickLookController(store: store, shelfPanel: panel)
        panel.quickLook = quickLook
        panel.title = L10n.text("Layby 文件停放区")
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
        surface = ShelfSurfaceView(frame: CGRect(origin: .zero, size: ShelfLayout.windowSize))
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
        panel.onSelectAll = { [weak store] in store?.selection = Set(store?.visibleReadyItems.map(\.id) ?? []) }
        panel.onDelete = { [weak store] in store?.removeSelection() }
        panel.onCopy = { [weak store] in store?.copySelection() }
        panel.onQuickLook = { [weak self] in self?.quickLook.toggle() ?? false }
        panel.onNavigate = { [weak store] direction in store?.moveSelection(direction) ?? false }
        panel.dismissQuickLook = { [weak self] in self?.quickLook.dismiss() ?? false }
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
            hide: { [weak self] in self?.hide() }, beginMoving: { [weak self] in
                self?.surface.stopAppearanceAnimation()
                self?.onBeginMoving?()
            },
            presentationChanged: { [weak self] in self?.resizeForPresentation() },
            preview: { [weak self] id in self?.quickLook.preview(id) }))
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
        surface.stopAppearanceAnimation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func show(near point: CGPoint, focus: Bool, notchScreen: NSScreen? = nil) {
        let wasVisible = panel.isVisible
        surface.stopAppearanceAnimation()
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
        surface.layoutSubtreeIfNeeded()
        if !wasVisible {
            surface.animateAppearance(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        panel.orderFrontRegardless()
        if focus { panel.makeKey() }
    }

    func hide() {
        quickLook.dismiss()
        surface.stopAppearanceAnimation()
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
        quickLook.stop()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    private func updateAccessibility() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { surface.stopAppearanceAnimation() }
        destination.wantsLayer = true
        destination.layer?.backgroundColor = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        destination.layer?.cornerRadius = ShelfLayout.cornerRadius
    }
}
