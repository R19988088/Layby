import AppKit
import Testing
@testable import LaybyKit

@MainActor @Suite(.serialized)
struct ShelfShadowTests {
    @Test func panelUsesTheNativeSystemProjection() throws {
        _ = NSApplication.shared
        let shelf = ShelfWindowController(store: ShelfStore())
        defer { shelf.stop() }
        #expect(shelf.panel.hasShadow)
        #expect((shelf.panel.contentView as? ShelfSurfaceView)?.layer?.shadowOpacity == 0)
    }
}
