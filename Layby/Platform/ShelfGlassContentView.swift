import AppKit

/// Receives the local appearance chosen by native glass from the content behind it.
@MainActor
final class ShelfGlassContentView: NSView {
    var onAppearanceChange: ((NSAppearance) -> Void)? {
        didSet { refreshAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAppearance()
    }

    func refreshAppearance() {
        updateBackground(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        onAppearanceChange?(effectiveAppearance)
    }

    func updateBackground(reduceTransparency: Bool) {
        // CGColor is a resolved snapshot; refresh it in this view's appearance,
        // including when accessibility settings change without a theme change.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        }
    }
}

/// Large glass surfaces keep the system appearance. A capsule-sized native surface
/// supplies background adaptation for every shelf size, at the persistent grip anchor.
@available(macOS 26.0, *)
@MainActor
final class ShelfBackdropAppearanceView: NSView {
    let content = ShelfGlassContentView(frame: .zero)
    var onAppearanceChange: ((NSAppearance) -> Void)? {
        didSet { refreshAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let effect = NSGlassEffectView()
        effect.style = .regular
        effect.cornerRadius = ShelfLayout.capsuleCornerRadius
        effect.contentView = content
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(false)
        setAccessibilityChildren([])
        content.onAppearanceChange = { [weak self] _ in self?.refreshAppearance() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        // With transparency disabled there is no backdrop to adapt to. Use the
        // inherited system appearance, including its increased-contrast variant.
        onAppearanceChange?(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? effectiveAppearance : content.effectiveAppearance)
    }
}
