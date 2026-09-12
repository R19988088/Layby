import AppKit
import Testing
@testable import LaybyKit

@MainActor @Suite(.serialized)
struct KeyboardNavigationTests {
    private func fixture() async throws -> (ShelfStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyNavigation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = (0..<8).map { root.appendingPathComponent("file\($0).txt") }
        for file in files { try Data("navigation".utf8).write(to: file) }
        let store = ShelfStore(managedFiles: ManagedFileStore(root: root.appendingPathComponent("managed")))
        store.add(files + [root.appendingPathComponent("missing.txt")])
        for _ in 0..<200 where store.items.contains(where: { $0.state == .loading }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        return (store, root)
    }

    @Test func listMovesOneFileAndPreservesBoundaryAndMultipleSelection() async throws {
        let (store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = store.items.map(\.id)
        store.present(.list)
        #expect(!store.moveSelection(.down))
        store.select(ids[0], extending: false)
        #expect(store.moveSelection(.up))
        #expect(store.selection == [ids[0]])
        #expect(store.moveSelection(.right))
        #expect(store.selection == [ids[1]])
        #expect(store.moveSelection(.down))
        #expect(store.selection == [ids[2]])
        #expect(store.moveSelection(.left))
        #expect(store.selection == [ids[1]])
        store.select(ids[2], extending: true)
        #expect(!store.moveSelection(.down))
        #expect(store.selection == Set(ids[1...2]))
        store.present(.stack)
        store.select(ids[0], extending: false)
        #expect(!store.moveSelection(.right))
    }

    @Test func gridUsesActualColumnsAndHandlesAnIncompleteLastRow() async throws {
        let (store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        store.remove(Set(store.items.filter { !$0.state.isReady }.map(\.id)))
        let ids = store.items.map(\.id)
        store.present(.grid)
        store.gridColumnCount = 3
        store.select(ids[2], extending: false)
        #expect(store.moveSelection(.down))
        #expect(store.selection == [ids[5]])
        #expect(store.moveSelection(.down))
        #expect(store.selection == [ids[7]])
        #expect(store.moveSelection(.down))
        #expect(store.selection == [ids[7]])
        #expect(store.moveSelection(.up))
        #expect(store.selection == [ids[4]])
        store.gridColumnCount = 2
        #expect(store.moveSelection(.up))
        #expect(store.selection == [ids[2]])
        #expect(store.moveSelection(.left))
        #expect(store.selection == [ids[1]])
        #expect(ShelfLayout.gridColumns(for: 476) == 3)
        #expect(ShelfLayout.gridColumns(for: 300) == 2)
        #expect(ShelfLayout.gridColumns(for: 120) == 1)
    }

    @Test func previewNavigationSkipsUnavailableFilesWithoutClosingSelection() async throws {
        let (store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = store.items.map(\.id)
        store.present(.list)
        store.select(ids[7], extending: false)
        #expect(store.moveSelection(.down, skippingUnavailable: true))
        #expect(store.selection == [ids[7]])
        #expect(store.moveSelection(.down))
        #expect(store.selection == [ids[8]])
        #expect(store.moveSelection(.up, skippingUnavailable: true))
        #expect(store.selection == [ids[7]])
    }

    @Test func arrowsAcceptNativeFlagsAndDoNotStealModifiedShortcuts() {
        func event(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f701}",
                charactersIgnoringModifiers: "\u{f701}", isARepeat: true, keyCode: 125)!
        }
        #expect(ShelfPanel.navigationDirection(for: event([.numericPad, .function])) == .down)
        for flag in [NSEvent.ModifierFlags.command, .shift, .control, .option] {
            #expect(ShelfPanel.navigationDirection(for: event(flag)) == nil)
        }
    }
}
