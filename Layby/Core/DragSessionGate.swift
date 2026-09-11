import Foundation

/// A fresh pasteboard generation is evidence, never authorization to import files.
struct DragSessionGate {
    private(set) var baseline: Int
    private(set) var token: UUID?
    private(set) var activated = false
    private(set) var cancelled = false
    private var pressed = false

    init(baseline: Int) { self.baseline = baseline }

    mutating func begin(changeCount: Int) {
        baseline = changeCount
        token = nil
        activated = false
        cancelled = false
        pressed = true
    }

    mutating func observe(changeCount: Int, supportsFiles: Bool) -> Bool {
        guard pressed, !cancelled else { return false }
        if token == nil, changeCount != baseline, supportsFiles { token = UUID() }
        return token != nil
    }

    mutating func consumeActivation() -> Bool {
        guard token != nil, !activated, !cancelled else { return false }
        activated = true
        return true
    }

    mutating func cancel() { cancelled = true; token = nil }

    mutating func end(changeCount: Int) {
        baseline = changeCount
        token = nil
        activated = false
        pressed = false
    }
}
