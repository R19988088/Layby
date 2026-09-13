import AppKit
import SwiftUI

/// Supplies the shelf's current files to the system-managed Services menu.
@MainActor
final class ShelfServicesController: NSObject, @MainActor NSServicesMenuRequestor {
    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let pathAliases = [NSPasteboard.PasteboardType("NSStringPboardType"), .init("NSPasteboardTypeString")]
    static let sendTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, filenamesType, .string] + pathAliases
    private let catalog: FileServiceCatalog
    private let performService: (String, NSPasteboard) -> Bool
    private let store: ShelfStore
    private weak var pendingServicesView: NSView?
    private var pendingServicesRequest: UUID?
    private var trackingServicesMenu: NSMenu?
    // Providers may open a URL asynchronously after the service has returned.
    // Keep access and managed files alive until this app session ends, even if
    // the user closes/clears the shelf in the meantime.
    private var sentLeases: [ObjectIdentifier: FileAccessLease] = [:]

    init(store: ShelfStore, catalog: FileServiceCatalog? = nil,
         performService: @escaping (String, NSPasteboard) -> Bool = { NSPerformService($0, $1) }) {
        self.store = store
        self.catalog = catalog ?? .shared
        self.performService = performService
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelServicesMenu),
            name: NSApplication.didResignActiveNotification, object: NSApp)
    }

    static func installMenu(in applicationMenu: NSMenu) {
        NSApp.registerServicesMenuSendTypes(sendTypes, returnTypes: [])
        let menu = NSMenu(title: L10n.text("服务"))
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        applicationMenu.insertItem(item, at: max(0, applicationMenu.numberOfItems - 2))
        NSApp.servicesMenu = menu
    }

    var items: [ShelfItem] {
        let candidates = store.presentation == .stack ? store.items
            : store.visibleItems.filter { store.selection.contains($0.id) }
        guard !candidates.isEmpty,
              candidates.allSatisfy({ $0.state.isReady && $0.url?.isFileURL == true && $0.lease != nil }) else { return [] }
        return candidates
    }

    func accepts(sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Bool {
        guard let sendType, Self.sendTypes.contains(sendType), returnType == nil else { return false }
        return !items.isEmpty
    }

    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        writeFiles(items, to: pasteboard, types: types)
    }

    private func writeFiles(_ selected: [ShelfItem], to pasteboard: NSPasteboard,
                            types: [NSPasteboard.PasteboardType]) -> Bool {
        guard !selected.isEmpty, types.contains(where: Self.sendTypes.contains) else { return false }
        let urls = selected.compactMap(\.url)
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            store.notice = "文件不可用，请重新检查后再使用服务"
            return false
        }
        pasteboard.clearContents()
        var written = false
        if types.contains(.fileURL) || types.contains(.URL) { written = pasteboard.writeObjects(urls as [NSURL]) }
        // File services such as Parallels request paths under string aliases,
        // while Dropover reads URL objects. Keep all URLs for multi-file input.
        let paths = urls.map(\.path).joined(separator: "\n")
        for type in [.string] + Self.pathAliases where types.contains(type) {
            pasteboard.addTypes([type], owner: nil)
            written = pasteboard.setString(paths, forType: type) || written
        }
        if types.contains(Self.filenamesType) {
            pasteboard.addTypes([Self.filenamesType], owner: nil)
            written = pasteboard.setPropertyList(urls.map(\.path), forType: Self.filenamesType) || written
        }
        if written {
            for item in selected {
                if let lease = item.lease { sentLeases[ObjectIdentifier(lease)] = lease }
            }
        }
        return written
    }

    func stop() {
        cancelServicesMenu()
        sentLeases.removeAll()
    }

    func prepareContext(for id: UUID) {
        // Right-clicking one of the selected files preserves the entire group.
        if !store.selection.contains(id) { store.select(id, extending: false) }
    }

    func contextMenu(for id: UUID, preview: @escaping (UUID) -> Void) -> NSMenu? {
        guard let item = store.visibleItems.first(where: { $0.id == id }) else { return nil }
        prepareContext(for: id)
        let menu = NSMenu()
        // Show the same explicit file-service list as the stack button, instead
        // of AppKit appending generic text/selection services to this menu.
        menu.allowsContextMenuPlugIns = false
        menu.automaticallyInsertsWritingToolsItems = false
        if item.isDirectory {
            menu.addItem(ShelfMenuAction("打开文件夹", enabled: item.state.isReady) { [store] in store.openFolder(id) })
        }
        menu.addItem(ShelfMenuAction("快速查看", enabled: item.state.isReady) { preview(id) })
        menu.addItem(.separator())
        if let url = item.url {
            menu.addItem(ShelfMenuAction("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            menu.addItem(ShelfMenuAction("重新检查") { [store] in store.retry(id) })
        }
        if !store.isBrowsingFolder {
            menu.addItem(ShelfMenuAction("从停放区移除") { [store] in store.remove([id]) })
        }
        menu.addItem(.separator())
        menu.addItem(ShelfMenuAction("清空停放区") { [store] in store.clear() })
        menu.addItem(.separator())
        let serviceItem = menu.addItem(withTitle: L10n.text("服务"), action: nil, keyEquivalent: "")
        serviceItem.submenu = fileServicesMenu()
        return menu
    }

    func showAllServices(from view: NSView) {
        guard pendingServicesRequest == nil, trackingServicesMenu == nil,
              canShowAllServices(from: view) else { return }
        let request = UUID()
        pendingServicesRequest = request
        pendingServicesView = view
        // Activation is asynchronous. Starting menu tracking before it finishes
        // makes AppKit dismiss the menu during the foreground transition.
        if NSApp.isActive {
            applicationDidBecomeActive()
        } else {
            NSApp.activate()
        }
        // Activation can be refused. Never reopen a stale click much later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.pendingServicesRequest == request else { return }
            self?.cancelServicesMenu()
        }
    }

    @objc private func applicationDidBecomeActive() {
        guard NSApp.isActive, let request = pendingServicesRequest else { return }
        guard let view = pendingServicesView, canShowAllServices(from: view),
              let window = view.window else {
            cancelServicesMenu()
            return
        }
        window.makeKey()
        window.makeFirstResponder(view)
        // Finish activation and the current click before entering NSMenu's
        // nested tracking loop.
        DispatchQueue.main.async { [weak self, weak view, weak window] in
            guard let self, self.pendingServicesRequest == request else { return }
            self.pendingServicesRequest = nil
            self.pendingServicesView = nil
            guard NSApp.isActive, let view, let window, view.window === window,
                  window.isKeyWindow, self.canShowAllServices(from: view) else { return }
            let menu = self.fileServicesMenu()
            self.trackingServicesMenu = menu
            defer { self.trackingServicesMenu = nil }
            let point = CGPoint(x: 0, y: view.isFlipped ? view.bounds.maxY : view.bounds.minY)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    private func canShowAllServices(from view: NSView) -> Bool {
        !items.isEmpty && store.presentation == .stack && !view.isHiddenOrHasHiddenAncestor
            && view.window?.isVisible == true
            && (view.window as? ShelfPanel)?.permitsFileServices == true
    }

    @objc func cancelServicesMenu() {
        pendingServicesRequest = nil
        pendingServicesView = nil
        trackingServicesMenu?.cancelTracking()
    }

    func fileServicesMenu() -> NSMenu {
        catalog.refreshIfNeeded()
        let menu = NSMenu(title: L10n.text("服务"))
        menu.allowsContextMenuPlugIns = false
        let selection = items
        let services = catalog.entries.filter { $0.accepts(selection) }
        let names = Dictionary(grouping: services, by: \.title)
        for service in services {
            let duplicate = (names[service.title]?.count ?? 0) > 1
            let title = duplicate ? "\(service.title) (\(service.applicationName))" : service.title
            menu.addItem(ShelfMenuAction(title) { [weak self] in
                self?.invoke(service, selection: selection, invocationName: duplicate ? title : service.invocationName)
            })
        }
        if services.isEmpty {
            menu.addItem(withTitle: L10n.text(catalog.isLoaded ? "没有适用的文件服务" : "正在读取文件服务…"),
                         action: nil, keyEquivalent: "")
        }
        return menu
    }

    /// Invoke the registered service on a private pasteboard; do not launch an
    /// arbitrary executable or substitute an application's default Open action.
    func invoke(_ service: FileService, selection: [ShelfItem], invocationName: String? = nil) {
        guard !selection.isEmpty, service.accepts(selection),
              selection.allSatisfy({ $0.state.isReady && $0.lease != nil && $0.url != nil }) else { return }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        guard writeFiles(selection, to: board, types: Self.sendTypes) else { return }
        if !performService(invocationName ?? service.invocationName, board) {
            store.notice = L10n.format("无法执行文件服务“%@”，请确认提供该服务的应用可用。", service.title)
        }
    }
}

@MainActor private final class ShelfMenuAction: NSMenuItem, NSMenuItemValidation {
    private let invoke: () -> Void
    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        invoke = action
        super.init(title: L10n.text(title), action: #selector(invokeAction), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invokeAction() { invoke() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isEnabled }
}

struct ShelfServicesButton: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> ShelfServicesButtonView { ShelfServicesButtonView() }
    func updateNSView(_ view: ShelfServicesButtonView, context: Context) { view.setEnabled(enabled) }
}

@MainActor final class ShelfServicesButtonView: NSView {
    private var host: NSHostingView<ServicesButtonContent>!
    init() {
        super.init(frame: .zero)
        host = NSHostingView(rootView: content(enabled: false))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor), host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    func setEnabled(_ enabled: Bool) { host.rootView = content(enabled: enabled) }
    private func content(enabled: Bool) -> ServicesButtonContent {
        ServicesButtonContent(enabled: enabled) { [weak self] in
            guard let self else { return }
            (self.window as? ShelfPanel)?.services?.showAllServices(from: self)
        }
    }
}

private struct ServicesButtonContent: View {
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                .frame(width: ShelfLayout.headerButtonSize, height: ShelfLayout.headerButtonSize)
        }
        .buttonStyle(ShelfSolidButtonStyle())
        .disabled(!enabled)
        .help(L10n.text("对全部文件使用服务"))
        .accessibilityLabel(L10n.text("对全部文件使用服务"))
    }
}
