import AppKit

// Run in a real accessory application's event loop. Swift Testing's command-line
// host does not provide NSApplication activation and menu tracking lifecycle.
@main
enum ServicesPopupSmoke {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = PopupTestDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.failed ? 1 : 0)
    }
}

@MainActor private final class PopupTestDelegate: NSObject, NSApplicationDelegate {
    var failed = false
    private var opened = 0
    private var closed = 0
    private var cancelled = false
    private var trackedMenu: ObjectIdentifier?
    private var dismissedEarly = false
    private var openedWithoutFocus = false
    private let previousApp = NSWorkspace.shared.frontmostApplication

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await exerciseMenu()
                print("PASS: inactive first request, activation wait, duplicate request, active request, collapse and hide cancellation")
            } catch {
                failed = true
                print("FAIL: \(error)")
            }
            fflush(stdout)
            previousApp?.activate()
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
    }

    private func exerciseMenu() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaybyPopupSmoke-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sample.txt")
        try Data("menu test".utf8).write(to: url)
        let store = ShelfStore()
        store.add([url])
        try await waitUntil("file inspection") { store.items.first?.state.isReady == true }
        let shelf = ShelfWindowController(store: store)
        defer { shelf.stop() }
        let anchor = ShelfServicesButtonView()
        shelf.show(near: CGPoint(x: 500, y: 500), focus: false)
        shelf.panel.contentView?.addSubview(anchor)
        anchor.frame = CGRect(x: 80, y: 80, width: 30, height: 30)

        let begin = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
            object: nil, queue: .main) { [self] notification in
                MainActor.assumeIsolated {
                    guard let menu = notification.object as? NSMenu else { return }
                    trackedMenu = ObjectIdentifier(menu)
                    opened += 1
                    cancelled = false
                    openedWithoutFocus = openedWithoutFocus || !NSApp.isActive || !shelf.panel.isKeyWindow
                    let timer = Timer(timeInterval: 0.3, repeats: false) { [self] _ in
                        MainActor.assumeIsolated {
                            cancelled = true
                            menu.cancelTracking()
                        }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        let end = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification,
            object: nil, queue: .main) { [self] notification in
                MainActor.assumeIsolated {
                    guard let menu = notification.object as? NSMenu,
                          ObjectIdentifier(menu) == trackedMenu else { return }
                    dismissedEarly = dismissedEarly || !cancelled
                    closed += 1
                }
            }
        defer {
            NotificationCenter.default.removeObserver(begin)
            NotificationCenter.default.removeObserver(end)
        }

        // Establish actual background state, including WindowServer events.
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        try await waitUntil("application to lose focus") { !NSApp.isActive }
        shelf.panel.services?.showAllServices(from: anchor)
        shelf.panel.services?.showAllServices(from: anchor)
        try check(opened == 0, "Menu opened before activation completed")
        // Automated invocation has no mouse event granting activation permission.
        // Grant it after the request; use real activation notifications thereafter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
        try await waitUntil("first menu to close deliberately") { closed == 1 }
        try check(opened == 1 && !dismissedEarly && !openedWithoutFocus,
                  "First menu flashed, opened without focus, or opened twice")

        shelf.panel.services?.showAllServices(from: anchor)
        try await waitUntil("active menu to close deliberately") { closed == 2 }
        try check(opened == 2 && !dismissedEarly, "Active menu did not remain open")

        shelf.panel.services?.showAllServices(from: anchor)
        shelf.collapse(animated: false)
        try await Task.sleep(for: .milliseconds(150))
        try check(opened == 2, "Pending menu opened after collapse")
        shelf.restore(animated: false)
        shelf.panel.services?.showAllServices(from: anchor)
        shelf.hide()
        try await Task.sleep(for: .milliseconds(150))
        try check(opened == 2, "Pending menu opened after hide")
    }

    private func waitUntil(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try check(condition(), "Timed out waiting for \(description)")
    }

    private func check(_ condition: Bool, _ description: String) throws {
        if !condition { throw Failure(description: description) }
    }

    private struct Failure: Error, CustomStringConvertible { let description: String }
}
