import AppKit
import Observation
import UniformTypeIdentifiers
import os

/// Directory pages are separate from the files parked on the shelf. Browsing
/// never adds children to the shelf or changes the original directory on disk.
@Observable @MainActor
final class ShelfFolderBrowser {
    private struct Page {
        let directory: ShelfItem
        var requestID = UUID()
        var items: [ShelfItem] = []
        var isLoading = true
        var error: String?
    }

    private var pages: [Page] = [] { didSet { onChange?() } }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    var directory: ShelfItem? { pages.last?.directory }
    var items: [ShelfItem] { pages.last?.items ?? [] }
    var isLoading: Bool { pages.last?.isLoading ?? false }
    var error: String? { pages.last?.error }
    var depth: Int { pages.count }

    func enter(_ directory: ShelfItem) {
        guard directory.isDirectory, directory.state.isReady, directory.lease != nil else { return }
        pages.append(Page(directory: directory))
        loadCurrentPage()
    }

    func back() { if !pages.isEmpty { pages.removeLast() } }
    func reset() { pages.removeAll() }

    func containsRoot(_ ids: Set<UUID>) -> Bool {
        pages.first.map { ids.contains($0.directory.id) } ?? false
    }

    func reload() {
        guard !pages.isEmpty else { return }
        pages[pages.count - 1].requestID = UUID()
        pages[pages.count - 1].items = []
        pages[pages.count - 1].isLoading = true
        pages[pages.count - 1].error = nil
        loadCurrentPage()
    }

    func updateThumbnail(_ id: UUID, image: NSImage) {
        guard let page = pages.indices.last, let index = pages[page].items.firstIndex(where: { $0.id == id }) else { return }
        pages[page].items[index].icon = image
    }

    private func loadCurrentPage() {
        guard let page = pages.last, let lease = page.directory.lease else { return }
        let requestID = page.requestID
        let managed = page.directory.isManaged
        let queue = queue
        Task { [weak self, lease] in
            let result: Result<[(URL, FileMetadata?)], Error> = await withCheckedContinuation { continuation in
                queue.addOperation {
                    continuation.resume(returning: Result {
                        let urls = try FileManager.default.contentsOfDirectory(at: lease.url,
                            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
                        return urls.map { ($0, try? FileMetadata.read($0)) }.sorted {
                            let leftFolder = $0.1?.isDirectory == true, rightFolder = $1.1?.isDirectory == true
                            if leftFolder != rightFolder { return leftFolder }
                            return $0.0.lastPathComponent.localizedStandardCompare($1.0.lastPathComponent) == .orderedAscending
                        }
                    })
                }
            }
            // Going back, refreshing or clearing invalidates the page's request.
            guard let self, let index = self.pages.firstIndex(where: { $0.requestID == requestID }) else { return }
            switch result {
            case .success(let entries):
                self.pages[index].items = entries.map { url, metadata in
                    let type = metadata?.isDirectory == true ? UTType.folder : (UTType(filenameExtension: url.pathExtension) ?? .data)
                    return ShelfItem(id: UUID(), url: url, name: url.lastPathComponent,
                        subtitle: metadata?.subtitle ?? "无法访问", state: metadata == nil ? .unavailable("无法访问") : .ready,
                        icon: NSWorkspace.shared.icon(for: type), identity: metadata?.identity,
                        byteCount: metadata?.byteCount, isDirectory: metadata?.isDirectory ?? false,
                        isManaged: managed, lease: FileAccessLease(url: url, parent: lease))
                }
            case .failure(let error):
                self.pages[index].error = "无法读取文件夹，请检查文件是否存在及访问权限。"
                Logger.files.error("Folder listing failed: \(error.localizedDescription, privacy: .private)")
            }
            self.pages[index].isLoading = false
        }
    }
}
