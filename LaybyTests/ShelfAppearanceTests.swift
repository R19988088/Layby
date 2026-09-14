import AppKit
import SwiftUI
import Testing
@testable import LaybyKit

@MainActor @Suite(.serialized)
struct ShelfAppearanceTests {
    @Test func glassAppearanceReachesEveryPresentationAndNestedHost() async throws {
        _ = NSApplication.shared
        let shelf = ShelfWindowController(store: ShelfStore())
        defer { shelf.stop() }
        let surface = try #require(shelf.panel.contentView)
        let fill: ShelfGlassContentView
        if #available(macOS 26.0, *) {
            let glass = try #require(surface.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.contentView is ShelfGlassContentView)
            let backdrop = try #require(surface.subviews.compactMap { $0 as? ShelfBackdropAppearanceView }.first)
            #expect(backdrop.hitTest(.zero) == nil)
            fill = backdrop.content
        } else {
            let glass = try #require(surface.subviews.compactMap { $0 as? NSVisualEffectView }.first)
            fill = try #require(glass.subviews.compactMap { $0 as? ShelfGlassContentView }.first)
        }
        let grip = try #require(shelf.dragHandle.layer?.sublayers?.first)
        var schemes: [ColorScheme] = []
        let nested = NSHostingView(rootView: AppearanceProbe { schemes.append($0) })
        nested.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        shelf.destination.addSubview(nested)
        defer { nested.removeFromSuperview() }
        for mode in [ShelfPresentation.stack, .grid, .list] {
            shelf.destination.store.present(mode)
            shelf.show(near: CGPoint(x: 500, y: 500), focus: false)
            for collapsed in [false, true] {
                if collapsed { shelf.collapse(animated: false) }
                #expect(shelf.isCollapsed == collapsed)
                for name in [NSAppearance.Name.darkAqua, .aqua, .darkAqua] {
                    // Model native glass selecting the opposite appearance to the window.
                    // Never force the panel in production: it would disable local adaptation.
                    shelf.panel.appearance = NSAppearance(named: name == .aqua ? .darkAqua : .aqua)
                    fill.appearance = NSAppearance(named: name)
                    surface.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(50))
                    #expect(shelf.destination.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
                    #expect(shelf.dragHandle.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
                    #expect(schemes.last == (name == .darkAqua ? .dark : .light))
                    for host in shelf.destination.subviews where host is NSHostingView<ShelfView> || host is NSHostingView<ShelfCapsuleView> {
                        #expect(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
                    }
                    if #available(macOS 26.0, *) {
                        let glass = try #require(surface.subviews.compactMap { $0 as? NSGlassEffectView }.first)
                        #expect(glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
                    }
                    let color = try #require(grip.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.genericGray) })
                    #expect(name == .darkAqua ? color.whiteComponent > 0.8 : color.whiteComponent < 0.3)
                    #expect(shelf.dragHandle.layer?.sublayers?.first === grip)
                    #expect(CATransform3DIsIdentity(shelf.destination.layer!.transform))
                }
            }
            shelf.restore(animated: false, focus: false)
        }
        // Recreated hosts after close must inherit the current local appearance too.
        shelf.hide()
        fill.appearance = NSAppearance(named: .aqua)
        shelf.show(near: CGPoint(x: 500, y: 500), focus: false)
        #expect(shelf.destination.subviews.allSatisfy {
            $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        })
    }

    @Test func opaqueAccessibilityBackgroundRefreshesWithLocalAppearance() throws {
        let fill = ShelfGlassContentView(frame: .zero)
        var colors: [CGColor] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            fill.appearance = NSAppearance(named: name)
            fill.updateBackground(reduceTransparency: true)
            let actual = try #require(fill.layer?.backgroundColor)
            fill.effectiveAppearance.performAsCurrentDrawingAppearance {
                #expect(actual == NSColor.windowBackgroundColor.cgColor)
            }
            colors.append(actual)
        }
        #expect(colors[0] != colors[1])
        fill.updateBackground(reduceTransparency: false)
        #expect(fill.layer?.backgroundColor?.alpha == 0)
    }
}

private struct AppearanceProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    let report: (ColorScheme) -> Void

    var body: some View {
        Color.clear.onChange(of: colorScheme, initial: true) { _, value in report(value) }
    }
}
