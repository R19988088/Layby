import Foundation
import CoreGraphics

struct PointerSample: Sendable {
    let point: CGPoint
    let time: TimeInterval
}

enum ShakeSensitivity: String, CaseIterable, Identifiable, Sendable {
    case gentle, balanced, deliberate
    var id: Self { self }
    var title: String {
        switch self {
        case .gentle: "轻轻摇晃"
        case .balanced: "适中"
        case .deliberate: "用力摇晃"
        }
    }
    var segment: CGFloat {
        switch self { case .gentle: 10; case .balanced: 14; case .deliberate: 20 }
    }
    var path: CGFloat {
        switch self { case .gentle: 65; case .balanced: 90; case .deliberate: 130 }
    }
}

/// Pure, bounded trajectory recognizer. Distances use screen points, not event counts.
struct ShakeRecognizer {
    private var samples: [PointerSample] = []

    mutating func reset() { samples.removeAll(keepingCapacity: true) }

    mutating func append(_ sample: PointerSample, sensitivity: ShakeSensitivity) -> Bool {
        if let last = samples.last, sample.time < last.time { reset() }
        samples.append(sample)
        samples.removeAll { sample.time - $0.time > 0.5 }
        if samples.count > 256 { samples.removeFirst(samples.count - 256) }
        guard samples.count >= 5, let first = samples.first else { return false }
        let points = samples.map(\.point)
        let path = zip(points, points.dropFirst()).reduce(CGFloat.zero) {
            $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
        let displacement = hypot(sample.point.x - first.point.x, sample.point.y - first.point.y)
        guard path >= sensitivity.path, displacement <= path * 0.5 else { return false }
        return reversals(points.map(\.x), threshold: sensitivity.segment) >= 3
            || reversals(points.map(\.y), threshold: sensitivity.segment) >= 3
    }

    /// A reversal only counts after travelling a full half-stroke from an extremum.
    private func reversals(_ values: [CGFloat], threshold: CGFloat) -> Int {
        guard var extremum = values.first else { return 0 }
        var direction: CGFloat = 0
        var count = 0
        for value in values.dropFirst() {
            let delta = value - extremum
            if direction == 0 {
                if abs(delta) >= threshold { direction = delta > 0 ? 1 : -1; extremum = value }
            } else if delta * direction >= 0 {
                extremum = value
            } else if abs(delta) >= threshold {
                count += 1
                direction *= -1
                extremum = value
            }
        }
        return count
    }
}
