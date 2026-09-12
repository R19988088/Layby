import AppKit
import UniformTypeIdentifiers
import os

/// Keeps a security scope alive for every asynchronous reader and outbound drag.
final class FileAccessLease: @unchecked Sendable {
    let url: URL
    private let scoped: Bool
    private let managedDirectory: ManagedFileDirectory?
    private let parent: FileAccessLease?
    init(url: URL, managedDirectory: ManagedFileDirectory? = nil, parent: FileAccessLease? = nil) {
        self.url = url
        self.managedDirectory = managedDirectory
        // Child files inherit the original folder's sandbox access and storage
        // lifetime, including after navigating back or closing the shelf.
        self.parent = parent
        scoped = url.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

/// A promise destination stays alive while its producer, readers, or exports use it.
/// Releasing the final owner removes only this app-created directory.
final class ManagedFileDirectory: @unchecked Sendable {
    let url: URL
    private let cleanupQueue: OperationQueue

    fileprivate init(url: URL, cleanupQueue: OperationQueue) {
        self.url = url
        self.cleanupQueue = cleanupQueue
    }

    deinit {
        let directory = url
        cleanupQueue.addOperation {
            do { try FileManager.default.removeItem(at: directory) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { }
            catch { Logger.files.error("Promise cleanup failed: \(error.localizedDescription, privacy: .private)") }
        }
    }
}

struct FileMetadata: Sendable {
    let identity: String
    let subtitle: String
    let isDirectory: Bool
    let byteCount: Int64?

    static func read(_ url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .fileResourceIdentifierKey, .volumeIdentifierKey])
        let identity: String
        if let fileID = values.fileResourceIdentifier, let volumeID = values.volumeIdentifier {
            identity = "\(volumeID):\(fileID)"
        } else {
            identity = url.standardizedFileURL.absoluteString
        }
        let isDirectory = values.isDirectory == true
        let subtitle = isDirectory ? "文件夹" : ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)
        return Self(identity: identity, subtitle: subtitle, isDirectory: isDirectory,
                    byteCount: isDirectory ? nil : values.fileSize.map(Int64.init))
    }
}

/// Only owns files materialized from promises, never the user's original URLs.
final class ManagedFileStore: @unchecked Sendable {
    let sessionDirectory: URL
    private let cleanupQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.layby.file-cleanup"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.layby.file-promises"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(root: URL? = nil) {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Layby/PromisedFiles", isDirectory: true)
        sessionDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Previous sessions have a seven-day grace period. The current session is never swept.
        queue.addOperation {
            let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            guard let directories = try? FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
                guard let values = try? directory.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]),
                      values.isDirectory == true, let created = values.creationDate, created < cutoff else { continue }
                do { try FileManager.default.removeItem(at: directory) }
                catch { Logger.files.error("Expired promise cleanup failed: \(error.localizedDescription, privacy: .private)") }
            }
        }
    }

    func makeDestination() throws -> ManagedFileDirectory {
        let url = sessionDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ManagedFileDirectory(url: url, cleanupQueue: cleanupQueue)
    }
}

/// The provider's userInfo retains this delegate, including its file-access lease.
final class FilePromiseExport: NSObject, NSFilePromiseProviderDelegate {
    private let lease: FileAccessLease
    private let queue: OperationQueue

    init(lease: FileAccessLease, queue: OperationQueue) { self.lease = lease; self.queue = queue }

    @MainActor func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        lease.url.lastPathComponent
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping ((any Error)?) -> Void) {
        do {
            try FileManager.default.copyItem(at: lease.url, to: url)
            completionHandler(nil)
        } catch {
            Logger.files.error("Outbound promise failed: \(error.localizedDescription, privacy: .private)")
            completionHandler(error)
        }
    }

    @MainActor func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
}

extension Logger {
    static let files = Logger(subsystem: "dev.layby.Layby", category: "Files")
    static let activation = Logger(subsystem: "dev.layby.Layby", category: "Activation")
}
