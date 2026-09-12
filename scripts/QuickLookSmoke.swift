import AppKit
import Quartz

/// Desktop integration check: real application event loop, shelf and Quick Look.
/// This briefly displays test windows and never reads the user's files.
@main enum QuickLookSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = SmokeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class SmokeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await runChecks() }
    }

    private func runChecks() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyQuickLook-\(UUID())")
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        let shelf = ShelfWindowController(store: store)
        var failed = false
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            if !condition { failed = true }
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("quick-look.txt")
            try Data("Layby native Quick Look integration check".utf8).write(to: file)
            store.add([file])
            for _ in 0..<200 where store.readyItems.isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let id = store.readyItems.first?.id else { throw CocoaError(.fileReadUnknown) }
            for mode in [ShelfPresentation.list, .grid] {
                store.present(mode)
                shelf.show(near: NSPoint(x: 450, y: 450), focus: true)
                store.select(id, extending: false)
                try await Task.sleep(for: .milliseconds(300))
                // FileDragView has a generic SwiftUI content type. Locate the real
                // row/card without duplicating that type in the test harness.
                let row = fileResponder(in: shelf.destination)
                check(row != nil && shelf.panel.makeFirstResponder(row), "\(mode): actual file row receives keys")
                postKey(49, characters: " ", to: shelf.panel)
                try await Task.sleep(for: .milliseconds(700))
                let preview = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
                check(preview?.isVisible == true, "\(mode): Space displays native panel")
                check(preview?.currentPreviewItem?.previewItemURL == file, "\(mode): native panel receives selected file")
                if let preview, preview.isVisible {
                    postKey(53, characters: "\u{1b}", to: preview)
                    try await Task.sleep(for: .milliseconds(300))
                    check(!preview.isVisible && store.items.count == 1, "\(mode): Escape closes only preview")
                    postKey(49, characters: " ", to: shelf.panel)
                    try await Task.sleep(for: .milliseconds(500))
                    check(preview.isVisible, "\(mode): Space reopens preview")
                    postKey(49, characters: " ", to: preview)
                    try await Task.sleep(for: .milliseconds(300))
                    check(!preview.isVisible && store.items.count == 1, "\(mode): Space closes only preview")
                }
            }
            postKey(49, characters: " ", to: shelf.panel)
            try await Task.sleep(for: .milliseconds(500))
            let preview = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
            check(preview?.isVisible == true, "preview opens before closing shelf")
            shelf.hide()
            try await Task.sleep(for: .milliseconds(300))
            check(preview?.isVisible == false && store.items.isEmpty, "closing shelf dismisses preview and clears references")
            check(FileManager.default.fileExists(atPath: file.path), "original file survives closing shelf")
        } catch { check(false, error.localizedDescription) }
        shelf.stop()
        try? FileManager.default.removeItem(at: root)
        fflush(stdout)
        exit(failed ? 1 : 0)
    }

    private func fileResponder(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).hasPrefix("FileDragView<") { return view }
        for child in view.subviews {
            if let row = fileResponder(in: child) { return row }
        }
        return nil
    }

    private func postKey(_ code: UInt16, characters: String, to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code)!
        NSApp.postEvent(event, atStart: false)
    }
}
