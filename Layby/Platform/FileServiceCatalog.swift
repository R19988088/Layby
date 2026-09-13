import AppKit
import UniformTypeIdentifiers

/// Public NSServices declarations, filtered for operations that accept files.
struct FileService: Sendable, Identifiable {
    let id: String
    let title: String
    let invocationName: String
    let applicationName: String
    let fileTypes: [String]

    func accepts(_ items: [ShelfItem]) -> Bool {
        guard !items.isEmpty else { return false }
        guard !fileTypes.isEmpty else { return true }
        return items.allSatisfy { item in
            guard let url = item.url else { return false }
            let type = item.isDirectory ? UTType.folder : (UTType(filenameExtension: url.pathExtension) ?? .data)
            return fileTypes.contains { identifier in
                identifier == UTType.fileURL.identifier || UTType(identifier).map { type.conforms(to: $0) } == true
            }
        }
    }

    static func declarations(in info: [String: Any], bundleURL: URL) -> [FileService] {
        let bundleID = info["CFBundleIdentifier"] as? String ?? bundleURL.path
        let appName = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
        return (info["NSServices"] as? [[String: Any]] ?? []).enumerated().compactMap { index, entry in
            guard let name = (entry["NSMenuItem"] as? [String: String])?["default"],
                  (entry["NSReturnTypes"] as? [String] ?? []).isEmpty,
                  (entry["NSRestricted"] as? Bool) != true else { return nil }
            let send = Set(entry["NSSendTypes"] as? [String] ?? [])
            let fileTypes = entry["NSSendFileTypes"] as? [String] ?? []
            let contexts = (entry["NSRequiredContext"] as? [[String: Any]])
                ?? (entry["NSRequiredContext"] as? [String: Any]).map { [$0] } ?? [[:]]
            let contextsForFiles = contexts.filter { context in
                let apps = (context["NSApplicationIdentifier"] as? [String])
                    ?? (context["NSApplicationIdentifier"] as? String).map { [$0] } ?? []
                // The user is requesting the file services exposed in Finder.
                // This affects discovery only; invocation still uses Layby's real
                // identity and NSPerformService enforces the system's restrictions.
                return apps.isEmpty || apps.contains("com.apple.finder") || apps.contains("dev.layby.Layby")
            }
            guard !contextsForFiles.isEmpty else { return nil }
            let fileFormats: Set<String> = ["NSFilenamesPboardType", "public.file-url", "NSURLPboardType", "public.url"]
            let pathContext = contextsForFiles.contains { $0["NSTextContent"] as? String == "FilePath" }
            guard !send.isDisjoint(with: fileFormats) || !fileTypes.isEmpty || pathContext else { return nil }
            let bundle = Bundle(url: bundleURL)
            let localized = bundle?.localizedString(forKey: name, value: name, table: "ServicesMenu") ?? name
            return FileService(id: "\(bundleID):\(index):\(name)",
                title: localized.components(separatedBy: "/").last ?? localized,
                invocationName: name, applicationName: appName, fileTypes: fileTypes)
        }
    }
}

@MainActor
final class FileServiceCatalog {
    static let shared = FileServiceCatalog()
    private(set) var entries: [FileService] = []
    private(set) var isLoaded = false
    private var loading: Task<Void, Never>?
    private var lastUpdated: Date?
    private let live: Bool

    init() { live = true; refresh() }
    init(entries: [FileService]) { live = false; self.entries = entries; isLoaded = true }

    func refreshIfNeeded() {
        if live, lastUpdated.map({ Date().timeIntervalSince($0) > 30 }) ?? true { refresh() }
    }

    func refresh() {
        guard loading == nil else { return }
        loading = Task { [weak self] in
            let entries = await Task.detached(priority: .utility) { Self.discover() }.value
            guard let self, !Task.isCancelled else { return }
            self.entries = entries
            self.isLoaded = true
            self.lastUpdated = Date()
            self.loading = nil
        }
    }

    nonisolated static func discover() -> [FileService] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications"),
                     URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Library/CoreServices"),
                     home.appendingPathComponent("Library/Services"), URL(fileURLWithPath: "/Library/Services"),
                     URL(fileURLWithPath: "/System/Library/Services")]
        var found: [String: FileService] = [:]
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                guard ["app", "service", "workflow"].contains(url.pathExtension) else { continue }
                walker.skipDescendants()
                guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                for service in FileService.declarations(in: info, bundleURL: url) where found[service.id] == nil {
                    found[service.id] = service
                }
            }
        }
        return found.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
