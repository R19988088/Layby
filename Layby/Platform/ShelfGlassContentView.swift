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
