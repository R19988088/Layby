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
                // Locate the real row/card through its native selection marker.
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
            try await checkSelection(shelf: shelf, store: store, root: root, check: check)
            try await checkFolders(shelf: shelf, store: store, root: root, check: check)
        } catch { check(false, error.localizedDescription) }
        shelf.stop()
        try? FileManager.default.removeItem(at: root)
        fflush(stdout)
        exit(failed ? 1 : 0)
    }

    private func fileResponder(in view: NSView) -> NSView? {
        if view is ShelfFileSelectionTarget { return view }
        for child in view.subviews {
            if let row = fileResponder(in: child) { return row }
        }
        return nil
    }

    private func checkSelection(shelf: ShelfWindowController, store: ShelfStore, root: URL,
                                check: (Bool, String) -> Void) async throws {
        let files = (0..<4).map { root.appendingPathComponent("selection-\($0).txt") }
        for (index, file) in files.enumerated() { try Data(repeating: 65, count: (index + 1) * 100).write(to: file) }
        store.add(files)
        for _ in 0..<200 where store.readyItems.count < 4 { try await Task.sleep(for: .milliseconds(10)) }
        guard store.readyItems.count == 4 else { throw CocoaError(.fileReadUnknown) }
        let ids = store.items.map(\.id)
        func fileViews(_ view: NSView) -> [NSView] {
            if view is ShelfFileSelectionTarget { return [view] }
            return view.subviews.flatMap(fileViews)
        }
        for mode in [ShelfPresentation.list, .grid] {
            store.present(mode)
            shelf.show(near: NSPoint(x: 450, y: 450), focus: true)
            try await Task.sleep(for: .milliseconds(500))
            let rows = fileViews(shelf.destination).sorted {
                let a = $0.convert($0.bounds, to: nil), b = $1.convert($1.bounds, to: nil)
                return abs(a.midY - b.midY) > 1 ? a.midY > b.midY : a.midX < b.midX
            }
            guard rows.count == 4, let background = shelf.panel.selectionBackground else {
                check(false, "\(mode): file rows and blank area are installed")
                continue
            }
            func center(_ row: NSView) -> NSPoint { row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil) }
            postClick(center(rows[0]), to: shelf.panel)
            try await Task.sleep(for: .milliseconds(150))
            check(store.selection == [ids[0]], "\(mode): clicking file selects it without background clearing")
            postClick(center(rows[3]), modifiers: .shift, to: shelf.panel)
            try await Task.sleep(for: .milliseconds(150))
            check(store.selection == Set(ids), "\(mode): Shift click selects the full range")
            postClick(center(rows[1]), modifiers: .shift, to: shelf.panel)
            try await Task.sleep(for: .milliseconds(150))
            check(store.selection == Set(ids.prefix(2)), "\(mode): Shift click shrinks the range")
            let size = ByteCountFormatter.string(fromByteCount: 300, countStyle: .file)
            check(store.selectionSummary == L10n.format("已选择 %d 个文件 · %@", 2, size), "\(mode): summary shows selected count and size")
            postKey(49, characters: " ", to: shelf.panel)
            try await Task.sleep(for: .milliseconds(400))
            let preview = QLPreviewPanel.shared()
            check(preview?.isVisible == true, "\(mode): selected range supports Quick Look")
            let blank = background.convert(NSPoint(x: background.bounds.midX, y: 2), to: nil)
            postClick(blank, to: shelf.panel)
            try await Task.sleep(for: .milliseconds(200))
            for _ in 0..<100 where preview?.isVisible == true { try await Task.sleep(for: .milliseconds(10)) }
            check(store.selection.isEmpty && store.selectionSummary == nil, "\(mode): clicking blank clears selection and its summary")
            check(preview?.isVisible == false, "\(mode): clearing selection closes Quick Look")
            postClick(center(rows[2]), modifiers: .shift, to: shelf.panel)
            try await Task.sleep(for: .milliseconds(150))
            check(store.selection == [ids[2]], "\(mode): blank click resets Shift anchor")
        }
    }

    private func checkFolders(shelf: ShelfWindowController, store: ShelfStore, root: URL,
                              check: (Bool, String) -> Void) async throws {
        shelf.hide()
        let folder = root.appendingPathComponent("Browse")
        let nested = folder.appendingPathComponent("Nested")
        let child = nested.appendingPathComponent("child.txt")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("child".utf8).write(to: child)
        store.add([folder])
        for _ in 0..<200 where store.readyItems.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let rootIDs = store.items.map(\.id)
        for mode in [ShelfPresentation.list, .grid] {
            store.present(mode)
            shelf.show(near: NSPoint(x: 450, y: 450), focus: true)
            try await Task.sleep(for: .milliseconds(400))
            for expectedDepth in 1...2 {
                guard let row = fileResponder(in: shelf.destination) else {
                    check(false, "\(mode): folder row exists")
                    break
                }
                let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
                postClick(point, to: shelf.panel)
                postClick(point, clickCount: 2, to: shelf.panel)
                try await Task.sleep(for: .milliseconds(400))
                for _ in 0..<100 where store.folderBrowser.isLoading { try await Task.sleep(for: .milliseconds(10)) }
                check(store.folderBrowser.depth == expectedDepth, "\(mode): double click enters folder level \(expectedDepth)")
            }
            check(store.visibleItems.first?.url?.resolvingSymlinksInPath() == child.resolvingSymlinksInPath(), "\(mode): nested child is displayed")
            if let id = store.visibleItems.first?.id {
                store.select(id, extending: false)
                postKey(49, characters: " ", to: shelf.panel)
                try await Task.sleep(for: .milliseconds(500))
                let preview = QLPreviewPanel.shared()
                check(preview?.currentPreviewItem?.previewItemURL?.resolvingSymlinksInPath() == child.resolvingSymlinksInPath(), "\(mode): Quick Look previews the child")
                if let preview { postKey(53, characters: "\u{1b}", to: preview) }
                try await Task.sleep(for: .milliseconds(400))
            }
            // Click the actual SwiftUI back button, using its shared layout constants.
            let inset = ShelfLayout.headerButtonInset + ShelfLayout.headerButtonSize / 2
            let backPoint = shelf.destination.convert(NSPoint(x: inset, y: shelf.destination.bounds.height - inset), to: nil)
            for expectedDepth in [1, 0] {
                postClick(backPoint, to: shelf.panel)
                try await Task.sleep(for: .milliseconds(400))
                check(store.folderBrowser.depth == expectedDepth, "\(mode): back button returns to level \(expectedDepth)")
            }
            check(store.visibleItems.map(\.id) == rootIDs && store.presentation == mode, "\(mode): root items and layout survive navigation")
        }
    }

    private func postClick(_ point: NSPoint, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1, to window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: clickCount, pressure: type == .leftMouseDown ? 1 : 0)!
            NSApp.postEvent(event, atStart: false)
        }
    }

    private func postKey(_ code: UInt16, characters: String, to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code)!
        NSApp.postEvent(event, atStart: false)
    }
}
