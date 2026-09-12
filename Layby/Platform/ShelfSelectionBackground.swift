import AppKit
import SwiftUI

struct ShelfSelectionBackground: NSViewRepresentable {
    let store: ShelfStore

    func makeNSView(context: Context) -> ShelfSelectionBackgroundView {
        ShelfSelectionBackgroundView(store: store)
    }

    func updateNSView(_ view: ShelfSelectionBackgroundView, context: Context) {}
}

/// Tracks the browser viewport and its padding without intercepting scrolling,
/// file dragging or SwiftUI buttons. The window dispatches mouse-down here first.
@MainActor final class ShelfSelectionBackgroundView: NSView {
    private let store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let panel = window as? ShelfPanel, panel.selectionBackground === self {
            panel.selectionBackground = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? ShelfPanel)?.selectionBackground = self
    }

    func handleMouseDown(_ event: NSEvent) {
        guard store.presentation.isExpanded, !store.selection.isEmpty, !isHiddenOrHasHiddenAncestor,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let root = window?.contentView else { return }
        var hit = root.hitTest(root.convert(event.locationInWindow, from: nil))
        while let view = hit {
            if view is ShelfFileSelectionTarget || view is NSControl { return }
            hit = view.superview
        }
        store.clearSelection()
        window?.makeFirstResponder(nil)
    }
}
