import AppKit
import Testing
@testable import LaybyKit

@MainActor @Suite(.serialized)
struct NotchHintTests {
    @Test func hintsOnlyRemainOnScreensWithoutVisibleShelves() async throws {
        _ = NSApplication.shared
        let suite = "LaybyNotchHints-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.topEdgeEnabled = true // Also exercise this on test hosts without a notch.
        let store = ShelfStore()
        let shelf = ShelfWindowController(store: store)
        let hints = NotchDropController(store: store, settings: settings)
        hints.hasShelfOnScreen = { shelf.isVisible(on: $0.frame) }
        defer { hints.hide(); shelf.stop() }
        let screen = try #require(NSScreen.main)
        let point = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        hints.setActive(true)
        #expect(hints.panels.count == NSScreen.screens.count)
        let pendingTarget = try #require(hints.panels.first { $0.screen === screen }?.panel.contentView as? DropDestinationView)
        var activations = 0
        hints.onActivate = { _ in activations += 1 }
        pendingTarget.onEnter?()
        shelf.show(near: point, focus: false)
        // The delayed hover must recheck presence even before the coordinator
        // has had a chance to remove the obsolete hint.
        try await Task.sleep(for: .milliseconds(200))
        #expect(activations == 0)
        #expect(hints.panels.allSatisfy { !shelf.isVisible(on: $0.screen.frame) })
        #expect(hints.panels.count == NSScreen.screens.filter { !shelf.isVisible(on: $0.frame) }.count)
        for compact in [false, true] {
            if compact { shelf.collapse(animated: false) }
            hints.setActive(true)
            #expect(hints.panels.allSatisfy { !shelf.isVisible(on: $0.screen.frame) })
            #expect(!hints.panels.contains { $0.screen === screen })
        }
        shelf.hide()
        hints.setActive(true)
        #expect(hints.panels.count == NSScreen.screens.count)
        shelf.show(near: point, focus: false)
        hints.suppressOccupiedScreens()
        #expect(!hints.panels.contains { $0.screen === screen })
        hints.setActive(false)
        #expect(hints.panels.isEmpty)
    }

    @Test func presenceIncludesBothSidesOfSpanningContentButExcludesShadowAndHiddenWindows() throws {
        _ = NSApplication.shared
        let shelf = ShelfWindowController(store: ShelfStore())
        defer { shelf.stop() }
        shelf.show(near: CGPoint(x: 500, y: 500), focus: false)
        let outer = shelf.panel.frame
        let content = outer.insetBy(dx: ShelfLayout.shadowInset, dy: ShelfLayout.shadowInset)
        let left = CGRect(x: content.minX - 100, y: content.minY, width: content.width / 2 + 100, height: content.height)
        let right = CGRect(x: content.midX, y: content.minY, width: content.width / 2 + 100, height: content.height)
        let shadowOnly = CGRect(x: outer.minX, y: outer.minY, width: ShelfLayout.shadowInset - 1, height: outer.height)
        #expect(shelf.isVisible(on: left) && shelf.isVisible(on: right))
        #expect(!shelf.isVisible(on: shadowOnly))
        #expect(!shelf.isVisible(on: outer.offsetBy(dx: -3000, dy: 0)))
        shelf.collapse(animated: false)
        #expect(shelf.isVisible(on: outer))
        shelf.hide()
        #expect(!shelf.isVisible(on: outer))
    }
}
