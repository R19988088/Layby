import AppKit

/// Uses real compositor backdrops, without screen capture or system preference changes.
@main enum AppearanceSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppearanceDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class AppearanceDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await runChecks() }
    }

    private func runChecks() async {
        guard #available(macOS 26.0, *), let screen = NSScreen.main,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            print("SKIP: native backdrop checks require macOS 26, a desktop and transparency")
            exit(2)
        }
        let background = NSWindow(contentRect: screen.visibleFrame.insetBy(dx: 30, dy: 30),
            styleMask: .borderless, backing: .buffered, defer: false)
        background.isReleasedWhenClosed = false
        background.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        background.orderFrontRegardless()
        let store = ShelfStore()
        let shelf = ShelfWindowController(store: store)
        guard let glass = shelf.panel.contentView?.subviews.compactMap({ $0 as? ShelfGlassView }).first else { exit(2) }
        var failures = 0
        // Change only this test app's base appearance; keep real system settings intact.
        for base in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: base)
            for mode in [ShelfPresentation.stack, .grid, .list] {
                shelf.hide()
                store.present(mode)
                shelf.show(near: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), focus: false)
                for collapsed in [false, true] {
                    if collapsed { shelf.collapse(animated: false) }
                    for white in [true, false, true] {
                        background.backgroundColor = white ? .white : .black
                        background.display()
                        let expected: NSAppearance.Name = collapsed ? (white ? .aqua : .darkAqua) : base
                        let views = [collapsed ? glass.capsuleContent : glass.expandedEffect, shelf.destination, shelf.dragHandle]
                        // Allow native material and NSAppearance propagation to settle.
                        try? await Task.sleep(for: .milliseconds(500))
                        for _ in 0..<15 {
                            if views.allSatisfy({ $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected }) { break }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        let passed = views.allSatisfy { $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected }
                        print("\(passed ? "PASS" : "FAIL"): base=\(base.rawValue) \(mode) capsule=\(collapsed) backdrop=\(white ? "white" : "black")")
                        if !passed { failures += 1 }
                        if collapsed {
                            shelf.restore(animated: false, focus: false)
                            background.backgroundColor = white ? .black : .white
                            background.display()
                            try? await Task.sleep(for: .milliseconds(500))
                            let retained = [glass.expandedEffect, glass.expandedContent, shelf.destination, shelf.dragHandle]
                                .allSatisfy { $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected }
                            print("\(retained ? "PASS" : "FAIL"): expansion retains capsule theme")
                            if !retained { failures += 1 }
                            shelf.collapse(animated: false)
                        }
                    }
                }
                shelf.restore(animated: false, focus: false)
            }
        }
        shelf.stop()
        background.close()
        print("Native backdrop checks: \(54 - failures)/54 passed")
        exit(failures == 0 ? 0 : 1)
    }
}
