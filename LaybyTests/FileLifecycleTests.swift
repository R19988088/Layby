import AppKit
import Testing
@testable import LaybyKit

@MainActor @Suite(.serialized)
struct FileLifecycleTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func settle(_ store: ShelfStore) async {
        for _ in 0..<200 {
            if !store.items.contains(where: { $0.state == .loading }) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func stackExportsAllAndCardExportsOnlyItself() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = (0..<8).map { root.appendingPathComponent("file-\($0).txt") }
        for file in files { try Data("file".utf8).write(to: file) }
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.add(files)
        await settle(store)
        let first = try #require(store.items.first?.id)
        let last = try #require(store.items.last?.id)
        store.select(first, extending: false)
        #expect(store.dragItems(for: .all).count == 8)
        store.selection = Set(store.items.map(\.id))
        #expect(store.dragItems(for: .item(last)).map(\.id) == [last])
        #expect(store.dragItems(for: .item(UUID())).isEmpty)
    }

    @Test func incompleteStackDoesNotSilentlyExportOnlySomeFiles() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("ready.txt")
        try Data("ready".utf8).write(to: file)
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.add([file, root.appendingPathComponent("missing.txt")])
        #expect(store.dragItems(for: .all).isEmpty)
        await settle(store)
        #expect(store.dragItems(for: .all).isEmpty)
        let readyID = try #require(store.readyItems.first?.id)
        #expect(store.dragItems(for: .item(readyID)).count == 1)
        store.remove(Set(store.items.filter { !$0.state.isReady }.map(\.id)))
        #expect(store.dragItems(for: .all).count == 1)
    }

    @Test func presentationResetsOnClearAndLastRemoval() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file.txt")
        try Data("file".utf8).write(to: file)
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.present(.grid)
        #expect(store.presentation == .stack)
        store.add([file])
        await settle(store)
        store.present(.grid)
        #expect(store.presentation == .grid)
        store.present(.list)
        #expect(store.presentation == .list)
        store.clear()
        #expect(store.presentation == .stack)
        store.add([file])
        await settle(store)
        store.present(.grid)
        store.remove(Set(store.items.map(\.id)))
        #expect(store.presentation == .stack)
    }

    private func waitForRemoval(_ url: URL) async {
        for _ in 0..<200 {
            if !FileManager.default.fileExists(atPath: url.path) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func closeRoutesClearTheShelfAndKeepOriginals() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("original.txt")
        try Data("keep".utf8).write(to: file)
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        let controller = ShelfWindowController(store: store)
        defer { controller.stop() }
        let actions: [() -> Void] = [
            { controller.hide() },
            { controller.panel.close() },
            { controller.panel.performClose(nil) },
            { controller.panel.cancelOperation(nil) },
            {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: 0, windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w",
                    isARepeat: false, keyCode: 13)!
                #expect(controller.panel.performKeyEquivalent(with: event))
            }
        ]
        for close in actions {
            store.add([file])
            await settle(store)
            store.selection = Set(store.items.map(\.id))
            store.notice = "已复制"
            store.isDropTargeted = true
            close()
            #expect(store.items.isEmpty)
            #expect(store.selection.isEmpty)
            #expect(store.notice == nil)
            #expect(!store.isDropTargeted)
            store.refreshReferences()
            #expect(store.items.isEmpty)
            #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
        }
    }

    @Test func clearDeletesManagedFilesAfterReadersRelease() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = ManagedFileStore(root: root)
        let store = ShelfStore(managedFiles: managed)
        var directory: ManagedFileDirectory? = try managed.makeDestination()
        let destination = try #require(directory?.url)
        let file = destination.appendingPathComponent("promise.txt")
        try Data("received".utf8).write(to: file)
        store.add([file], managedDirectory: directory)
        directory = nil
        await settle(store)
        var outboundLease: FileAccessLease? = store.items.first?.lease
        store.clear()
        #expect(store.items.isEmpty)
        #expect(try String(contentsOf: try #require(outboundLease?.url), encoding: .utf8) == "received")
        outboundLease = nil
        await waitForRemoval(destination)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func latePromiseAfterCloseIsDeletedWithoutReappearing() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root))
        let receiver = DelayedPromiseReceiver()
        #expect(store.receivePromise(receiver))
        let destination = try #require(receiver.destination)
        store.clear()
        // The producer still owns its destination, even though its shelf has been closed.
        #expect(FileManager.default.fileExists(atPath: destination.path))
        try receiver.deliver()
        await waitForRemoval(destination)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func duplicateURLIsIgnoredButSameNamesAreRetained() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.txt")
        let directory = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let second = directory.appendingPathComponent("a.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        #expect(store.add([first, first, second]) == 2)
        await settle(store)
        #expect(store.readyItems.count == 2)
        store.clear()
        #expect(try String(contentsOf: first, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
    }

    @Test func clearInvalidatesLateMetadata() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.txt")
        try Data("keep me".utf8).write(to: file)
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.add([file])
        store.clear()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func unavailableFileCanBeRetried() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("later.txt")
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.add([file])
        await settle(store)
        #expect(store.readyItems.isEmpty)
        let id = try #require(store.items.first?.id)
        try Data("now available".utf8).write(to: file)
        store.retry(id)
        await settle(store)
        #expect(store.readyItems.count == 1)
    }

    @Test func deletingReferencesDoesNotDeleteOriginals() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keep.txt")
        try Data("original".utf8).write(to: file)
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.add([file])
        await settle(store)
        let id = try #require(store.items.first?.id)
        store.select(id, extending: false)
        store.remove([id])
        #expect(store.selection.isEmpty)
        #expect(store.items.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }
}

private final class DelayedPromiseReceiver: NSFilePromiseReceiver {
    var destination: URL?
    private var reader: ((URL, Error?) -> Void)?

    override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any],
                                       operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
        destination = destinationDir
        self.reader = reader
    }

    func deliver() throws {
        let file = try #require(destination).appendingPathComponent("late.txt")
        try Data("late result".utf8).write(to: file)
        reader?(file, nil)
        reader = nil
    }
}
