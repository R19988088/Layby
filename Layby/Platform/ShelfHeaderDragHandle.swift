import AppKit
import QuartzCore
import SwiftUI

enum ShelfLayout {
    static let size = CGSize(width: 220, height: 220)
    static let expandedSize = CGSize(width: 500, height: 360)
    static let cornerRadius: CGFloat = 26
    static let headerButtonSize: CGFloat = 30
    // Match the button centers to the corner centers, with equal top and side insets.
    static var headerButtonInset: CGFloat { max(0, cornerRadius - headerButtonSize / 2) }
    static let shadowInset: CGFloat = 20
    static let windowSize = CGSize(width: size.width + shadowInset * 2, height: size.height + shadowInset * 2)
    static func windowSize(for presentation: ShelfPresentation) -> CGSize {
        let content = presentation.isExpanded ? expandedSize : size
        return CGSize(width: content.width + shadowInset * 2, height: content.height + shadowInset * 2)
    }
}

/// A fixed hit area contains the animated grip, so expansion never changes the hover boundary.
struct ShelfHeaderDragHandle: NSViewRepresentable {
    let onBeginDragging: () -> Void

    func makeNSView(context: Context) -> HeaderDragView {
        let view = HeaderDragView()
        view.onBeginDragging = onBeginDragging
        return view
    }

    func updateNSView(_ view: HeaderDragView, context: Context) {
        view.onBeginDragging = onBeginDragging
    }

    static func dismantleNSView(_ view: HeaderDragView, coordinator: ()) {
        view.stopTrackingDrag()
    }
}

@MainActor
final class HeaderDragView: NSView {
    var onBeginDragging: (() -> Void)?
    private let grip = CALayer()
    private var hoverArea: NSTrackingArea?
    private var dragEndTimer: Timer?
    private var isHovered = false
    private var isDraggingWindow = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        grip.bounds = CGRect(x: 0, y: 0, width: 80, height: 3)
        grip.cornerRadius = 1.5
        layer?.addSublayer(grip)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("移动停放区")
        setAccessibilityHelp("按住顶部横条并拖动，可以移动窗口")
        updateGrip(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grip.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        hoverArea = area
        addTrackingArea(area)
        refreshHover(animated: false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopTrackingDrag() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGrip(animated: false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isDraggingWindow ? .closedHand : .openHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateGrip(animated: true)
        if !isDraggingWindow { NSCursor.openHand.set() }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateGrip(animated: true)
        if !isDraggingWindow { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onBeginDragging?()
        isDraggingWindow = true
        updateGrip(animated: true)
        NSCursor.closedHand.set()
        window.invalidateCursorRects(for: self)

        // Window Server handles the original press, including holds, screen edges and Spaces.
        // performDrag returns immediately and may consume mouseUp, so watch release only while moving.
        dragEndTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 || self.window?.isVisible != true {
                    self.stopTrackingDrag()
                }
            }
        }
        dragEndTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        window.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) { stopTrackingDrag() }

    func stopTrackingDrag() {
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        guard isDraggingWindow else { return }
        isDraggingWindow = false
        refreshHover(animated: true)
        window?.invalidateCursorRects(for: self)
        if isHovered { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
    }

    private func refreshHover(animated: Bool) {
        isHovered = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        updateGrip(animated: animated)
    }

    private func updateGrip(animated: Bool) {
        let expanded = isHovered || isDraggingWindow
        let scale: CGFloat = expanded ? 1 : 0.32
        let opacity: Float = isDraggingWindow ? 0.8 : (expanded ? 0.58 : 0.22)
        let currentScale = grip.presentation()?.value(forKeyPath: "transform.scale.x") ?? grip.value(forKeyPath: "transform.scale.x")
        let currentOpacity = grip.presentation()?.opacity ?? grip.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance { grip.backgroundColor = NSColor.labelColor.cgColor }
        grip.transform = CATransform3DMakeScale(scale, 1, 1)
        grip.opacity = opacity
        CATransaction.commit()
        grip.removeAllAnimations()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let stretch = CABasicAnimation(keyPath: "transform.scale.x")
        stretch.fromValue = currentScale
        stretch.toValue = scale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = currentOpacity
        fade.toValue = opacity
        let group = CAAnimationGroup()
        group.animations = [stretch, fade]
        group.duration = expanded ? 0.18 : 0.14
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.25, 1)
        grip.add(group, forKey: "hover")
    }
}
