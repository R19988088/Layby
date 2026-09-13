import AppKit
import SwiftUI
import Testing
@testable import LaybyKit

@MainActor @Suite(.serialized)
struct ShelfServicesTests {
    private func settle(_ store: ShelfStore) async throws {
        for _ in 0..<200 {
            if !store.items.contains(where: { $0.state == .loading }) && !store.folderBrowser.isLoading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("File inspection did not finish")
    }

    private func files(in root: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ["one.txt", "two.txt", "three.txt"].map { name in
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
    }

    @Test func stackSendsEveryFileAsModernURLsAndLegacyFilenames() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyServices-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = try files(in: root)
        let store = ShelfStore()
        store.add(urls)
        try await settle(store)
        store.selection = [try #require(store.items.first?.id)]
        let services = ShelfServicesController(store: store)
        defer { services.stop(); store.clear() }
        #expect(services.items.map(\.url) == urls)
        #expect(services.accepts(sendType: .fileURL, returnType: nil))
        #expect(services.accepts(sendType: ShelfServicesController.filenamesType, returnType: nil))
        #expect(services.accepts(sendType: .string, returnType: nil))
        #expect(!services.accepts(sendType: .fileURL, returnType: .string))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(services.writeSelection(to: board, types: ShelfServicesController.sendTypes))
        #expect(board.propertyList(forType: ShelfServicesController.filenamesType) as? [String] == urls.map(\.path))
        let written = (board.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        #expect(written == urls)
        #expect(services.writeSelection(to: board, types: [ShelfServicesController.filenamesType]))
        #expect(board.propertyList(forType: ShelfServicesController.filenamesType) as? [String] == urls.map(\.path))
    }

    @Test func rightClickPreservesMultiSelectionAndUsesThePanelRequestor() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyServiceSelection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore()
        store.add(try files(in: root))
        try await settle(store)
        let shelf = ShelfWindowController(store: store)
        defer { shelf.stop() }
        let services = try #require(shelf.panel.services)
        for mode in [ShelfPresentation.grid, .list] {
            store.present(mode)
            shelf.show(near: CGPoint(x: 500, y: 500), focus: false)
            let ids = store.items.map(\.id)
            store.selection = [ids[0], ids[2]]
            let view = FileDragView(store: store, scope: .item(ids[2]), content: Text("Test file"))
            shelf.panel.contentView?.addSubview(view)
            defer { view.removeFromSuperview() }
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: shelf.panel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let menu = try #require(view.menu(for: event))
            #expect(!menu.allowsContextMenuPlugIns)
            #expect(store.selection == [ids[0], ids[2]])
            #expect(services.items.map(\.id) == [ids[0], ids[2]])
            #expect(shelf.panel.firstResponder === view)
            let requestor = shelf.panel.validRequestor(forSendType: .fileURL, returnType: nil)
            #expect((requestor as? ShelfServicesController) === services)
            services.prepareContext(for: ids[1])
            #expect(store.selection == [ids[1]])
            #expect(services.items.map(\.id) == [ids[1]])
        }
    }

    @Test func unavailableGroupsNeverSendPartialSelections() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyServiceUnavailable-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = try files(in: root)
        let store = ShelfStore()
        let services = ShelfServicesController(store: store)
        defer { services.stop(); store.clear() }
        #expect(services.items.isEmpty)
        store.add(urls)
        #expect(services.items.isEmpty)
        try await settle(store)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("unchanged", forType: .string)
        #expect(!services.writeSelection(to: board, types: [.rtf]))
        #expect(board.string(forType: .string) == "unchanged")
        try FileManager.default.removeItem(at: urls[1])
        #expect(!services.writeSelection(to: board, types: [.fileURL]))
        #expect(board.string(forType: .string) == "unchanged")
        #expect(store.notice != nil)
        store.add([root.appendingPathComponent("missing.txt")])
        try await settle(store)
        #expect(services.items.isEmpty)
        store.present(.list)
        store.selection = [store.items[0].id, try #require(store.items.last?.id)]
        #expect(services.items.isEmpty)
        store.selection = [store.items[0].id]
        #expect(services.items.count == 1)
    }

    @Test func servicesKeepManagedFolderChildrenAliveAfterClosingShelf() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyServiceLifetime-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = ManagedFileStore(root: root)
        var directory: ManagedFileDirectory? = try managed.makeDestination()
        let folder = try #require(directory?.url)
        let urls = try files(in: folder)
        let store = ShelfStore(managedFiles: managed)
        let shelf = ShelfWindowController(store: store)
        defer { shelf.stop() }
        store.add([folder], managedDirectory: directory)
        directory = nil
        try await settle(store)
        store.present(.grid)
        store.openFolder(try #require(store.items.first?.id))
        try await settle(store)
        store.selection = Set(store.visibleItems.map(\.id))
        let services = try #require(shelf.panel.services)
        #expect(Set(services.items.compactMap { $0.url?.resolvingSymlinksInPath() }) == Set(urls.map { $0.resolvingSymlinksInPath() }))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(services.writeSelection(to: board, types: [.fileURL]))
        shelf.hide()
        try await Task.sleep(for: .milliseconds(80))
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        services.stop()
        for _ in 0..<100 {
            if !FileManager.default.fileExists(atPath: folder.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func applicationRegistersAnActualSystemServicesMenu() {
        _ = NSApplication.shared
        let previous = NSApp.servicesMenu
        defer { NSApp.servicesMenu = previous }
        let applicationMenu = NSMenu(title: "Layby")
        ShelfServicesController.installMenu(in: applicationMenu)
        #expect(NSApp.servicesMenu != nil)
        #expect(NSApp.servicesMenu?.supermenu === applicationMenu)
    }
}
