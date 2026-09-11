import AppKit

/// A real AppKit drag destination. The observation service never imports data.
@MainActor
final class DropDestinationView: NSView {
    let store: ShelfStore
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onReceive: (() -> Void)?
    private(set) var isReceiving = false

    init(store: ShelfStore) {
        self.store = store
        super.init(frame: .zero)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL] + promiseTypes)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = allowedOperation(sender)
        if operation != [] { store.isDropTargeted = true; onEnter?() }
        return operation
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = allowedOperation(sender)
        store.isDropTargeted = operation != []
        return operation
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { allowedOperation(sender) != [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceiving = true
        defer { isReceiving = false; store.isDropTargeted = false }
        let accepted = store.receive(sender)
        if accepted { onReceive?() }
        return accepted
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { store.isDropTargeted = false; onExit?() }
    override func draggingEnded(_ sender: NSDraggingInfo) { store.isDropTargeted = false }

    private func allowedOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !store.isDraggingOut, sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self],
                  options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }
}
