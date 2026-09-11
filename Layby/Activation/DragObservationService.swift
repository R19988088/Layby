import AppKit
import ApplicationServices
import Observation
import os

enum ActivationReason { case shake, modifier, notch, hotKey, manual }

@Observable @MainActor
final class DragObservationService {
    private(set) var isTracking = false
    private(set) var observedDragCount = 0
    private(set) var hasAccessibilityTrust = false
    @ObservationIgnored var onActivation: ((ActivationReason, CGPoint) -> Void)?
    @ObservationIgnored var onActivityChange: ((Bool) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let store: ShelfStore
    @ObservationIgnored private let pasteboard = NSPasteboard(name: .drag)
    @ObservationIgnored private var gate: DragSessionGate
    @ObservationIgnored private var recognizer = ShakeRecognizer()
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var beganAt: TimeInterval = 0
    @ObservationIgnored private var lastMovement: TimeInterval = 0
    @ObservationIgnored private var lastPoint: CGPoint = .zero
    @ObservationIgnored private var sawDragEvent = false
    @ObservationIgnored private var lastTriggered: TimeInterval = -.infinity
    @ObservationIgnored private var observedChangeCount: Int
    @ObservationIgnored private var supportsFiles = false

    init(settings: AppSettings, store: ShelfStore) {
        self.settings = settings
        self.store = store
        let baseline = NSPasteboard(name: .drag).changeCount
        gate = DragSessionGate(baseline: baseline)
        observedChangeCount = baseline
    }

    func start() {
        guard monitors.isEmpty else { return }
        hasAccessibilityTrust = AXIsProcessTrusted()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) { monitors.append(monitor) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        finish()
    }

    func reset() { finish() }
    func refreshPermission() { hasAccessibilityTrust = AXIsProcessTrusted() }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            finish()
            begin(baseline: pasteboard.changeCount)
        case .leftMouseDragged:
            guard !store.isDraggingOut else { finish(); return }
            // Some tracking modes omit mouseDown. Use the last idle generation, never current stale data.
            if timer == nil { begin(baseline: gate.baseline) }
            sawDragEvent = true
            sample()
        case .leftMouseUp: finish()
        case .flagsChanged: if timer != nil { sample() }
        case .keyDown:
            if event.keyCode == 53 { gate.cancel(); finish() }
        default: break
        }
    }

    private func begin(baseline: Int) {
        gate.begin(changeCount: baseline)
        recognizer.reset()
        beganAt = ProcessInfo.processInfo.systemUptime
        lastMovement = beganAt
        lastPoint = NSEvent.mouseLocation
        sawDragEvent = false
        supportsFiles = false
        observedChangeCount = baseline
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sample() {
        guard NSEvent.pressedMouseButtons & 1 != 0, !store.isDraggingOut else { finish(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let point = NSEvent.mouseLocation
        if point != lastPoint { lastMovement = now; lastPoint = point }
        guard now - beganAt < 120, now - lastMovement < 30 else { finish(); return }
        let count = pasteboard.changeCount
        if count != observedChangeCount {
            observedChangeCount = count
            // Metadata only. Never read URLs or fulfill promises from the global pasteboard.
            let types = Set(pasteboard.types ?? [])
            supportsFiles = types.contains(.fileURL)
                || NSFilePromiseReceiver.readableDraggedTypes.contains { types.contains(NSPasteboard.PasteboardType($0)) }
        }
        guard sawDragEvent, gate.observe(changeCount: count, supportsFiles: supportsFiles) else { return }
        if !isTracking {
            isTracking = true
            observedDragCount += 1
            onActivityChange?(true)
        }
        let excluded = settings.excludes(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        guard !excluded, now - lastTriggered >= 0.8 else { return }
        if settings.modifierEnabled, NSEvent.modifierFlags.contains(settings.modifier.flag) {
            activate(.modifier, point: point, time: now)
        } else if settings.shakeEnabled,
                  recognizer.append(PointerSample(point: point, time: now), sensitivity: settings.sensitivity) {
            activate(.shake, point: point, time: now)
        }
    }

    private func activate(_ reason: ActivationReason, point: CGPoint, time: TimeInterval) {
        guard gate.consumeActivation() else { return }
        lastTriggered = time
        onActivation?(reason, point)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        gate.end(changeCount: pasteboard.changeCount)
        recognizer.reset()
        sawDragEvent = false
        if isTracking { isTracking = false; onActivityChange?(false) }
    }
}
