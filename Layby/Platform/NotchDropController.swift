import AppKit
import SwiftUI

@MainActor
final class NotchDropController {
    private let store: ShelfStore
    private let settings: AppSettings
    private(set) var panels: [(screen: NSScreen, panel: NSPanel)] = []
    var hasShelfOnScreen: (NSScreen) -> Bool = { _ in false }
    private var dwell: Task<Void, Never>?
    private var dwellScreen: NSScreen?
    var onActivate: ((NSScreen) -> Void)?
    var onReceive: ((NSScreen) -> Void)?

    init(store: ShelfStore, settings: AppSettings) { self.store = store; self.settings = settings }

    func setActive(_ active: Bool) {
        hide()
        guard active, settings.notchEnabled else { return }
        for screen in NSScreen.screens {
            guard !hasShelfOnScreen(screen) else { continue }
            let notch = ShelfGeometry.notch(frame: screen.frame, topInset: screen.safeAreaInsets.top,
                                            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
            guard (notch != nil && settings.notchEnabled) || (notch == nil && settings.topEdgeEnabled) else { continue }
            let frame: CGRect
            if let notch { frame = CGRect(x: notch.minX - 6, y: notch.minY - 30, width: notch.width + 12, height: notch.height + 30) }
            else { frame = CGRect(x: screen.frame.midX - 90, y: screen.frame.maxY - 32, width: 180, height: 32) }
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let target = DropDestinationView(store: store)
            let host = NSHostingView(rootView: NotchHint())
            host.translatesAutoresizingMaskIntoConstraints = false
            target.addSubview(host)
            NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: target.leadingAnchor), host.trailingAnchor.constraint(equalTo: target.trailingAnchor),
                                         host.bottomAnchor.constraint(equalTo: target.bottomAnchor), host.heightAnchor.constraint(equalToConstant: 28)])
            target.onEnter = { [weak self] in
                guard let self else { return }
                self.dwell?.cancel()
                self.dwellScreen = screen
                self.dwell = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    // A shortcut or another activation may show the shelf while
                    // this delayed hover is pending.
                    guard !self.hasShelfOnScreen(screen) else {
                        self.suppressOccupiedScreens()
                        return
                    }
                    self.onActivate?(screen)
                }
            }
            target.onExit = { [weak self] in self?.dwell?.cancel() }
            target.onReceive = { [weak self] in self?.dwell?.cancel(); self?.onReceive?(screen) }
            panel.contentView = target
            panel.orderFrontRegardless()
            panels.append((screen, panel))
        }
    }

    /// Remove just the now-redundant targets, preserving targets on other screens.
    func suppressOccupiedScreens() {
        if let screen = dwellScreen, hasShelfOnScreen(screen) {
            dwell?.cancel()
            dwell = nil
            dwellScreen = nil
        }
        panels.removeAll { entry in
            guard hasShelfOnScreen(entry.screen) else { return false }
            entry.panel.orderOut(nil)
            return true
        }
    }

    func hide() {
        dwell?.cancel()
        dwell = nil
        dwellScreen = nil
        panels.forEach { $0.panel.orderOut(nil) }
        panels.removeAll()
    }
}

private struct NotchHint: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tray.and.arrow.down")
            Text(L10n.text("暂放到 Layby"))
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 12).padding(.vertical, 5)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
