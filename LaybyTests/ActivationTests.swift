import Foundation
import Testing
@testable import LaybyKit

struct ActivationTests {
    @Test func shakeRecognizesBothAxes() {
        for vertical in [false, true] {
            var recognizer = ShakeRecognizer()
            let positions: [CGFloat] = [0, 30, -20, 30, -20, 15]
            var triggered = false
            for (index, value) in positions.enumerated() {
                let point = vertical ? CGPoint(x: 100, y: value) : CGPoint(x: value, y: 100)
                triggered = recognizer.append(PointerSample(point: point, time: Double(index) * 0.06), sensitivity: .balanced) || triggered
            }
            #expect(triggered)
        }
    }

    @Test func rejectsStraightLineAndJitter() {
        for jitter in [false, true] {
            var recognizer = ShakeRecognizer()
            for index in 0..<100 {
                let x = jitter ? CGFloat(index % 2) * 2 : CGFloat(index) * 8
                let result1 = !recognizer.append(PointerSample(point: CGPoint(x: x, y: 0), time: Double(index) * 0.005), sensitivity: .balanced)
                #expect(result1)
            }
        }
    }

    @Test func oldStrokesExpire() {
        var recognizer = ShakeRecognizer()
        for (index, value) in [0, 40, -40, 40, -40].enumerated() {
            let result2 = !recognizer.append(PointerSample(point: CGPoint(x: value, y: 0), time: Double(index)), sensitivity: .balanced)
            #expect(result2)
        }
    }

    @Test func recognitionDoesNotDependOnEventRate() {
        for samplesPerStroke in [4, 16, 32] {
            var recognizer = ShakeRecognizer()
            var recognized = false
            let endpoints: [CGFloat] = [0, 40, -30, 40, -30]
            for stroke in 0..<4 {
                for index in 0..<samplesPerStroke {
                    let fraction = CGFloat(index) / CGFloat(samplesPerStroke)
                    let x = endpoints[stroke] + (endpoints[stroke + 1] - endpoints[stroke]) * fraction
                    let time = (Double(stroke) + Double(fraction)) * 0.1
                    recognized = recognizer.append(PointerSample(point: CGPoint(x: x, y: 0), time: time), sensitivity: .balanced) || recognized
                }
            }
            #expect(recognized)
        }
    }

    @Test func stalePasteboardAndNonFileDragsAreRejected() {
        var gate = DragSessionGate(baseline: 10)
        gate.begin(changeCount: 10)
        let result3 = !gate.observe(changeCount: 10, supportsFiles: true)
        #expect(result3)
        let result4 = !gate.observe(changeCount: 11, supportsFiles: false)
        #expect(result4)
        let result5 = !gate.consumeActivation()
        #expect(result5)
        let result6 = gate.observe(changeCount: 12, supportsFiles: true)
        #expect(result6)
        let result7 = gate.consumeActivation()
        #expect(result7)
        let result8 = !gate.consumeActivation()
        #expect(result8)
    }

    @Test func cancellationAndReleaseRequireNewSession() {
        var gate = DragSessionGate(baseline: 0)
        gate.begin(changeCount: 0)
        let result9 = gate.observe(changeCount: 1, supportsFiles: true)
        #expect(result9)
        gate.cancel()
        let result10 = !gate.observe(changeCount: 2, supportsFiles: true)
        #expect(result10)
        gate.end(changeCount: 2)
        let result11 = !gate.observe(changeCount: 3, supportsFiles: true)
        #expect(result11)
        gate.begin(changeCount: 3)
        let result12 = !gate.observe(changeCount: 3, supportsFiles: true)
        #expect(result12)
        let result13 = gate.observe(changeCount: 4, supportsFiles: true)
        #expect(result13)
        let result14 = gate.consumeActivation()
        #expect(result14)
    }

    @Test func panelStaysOnNegativeCoordinateDisplay() {
        let bounds = CGRect(x: -1920, y: -600, width: 1920, height: 1080)
        for point in [CGPoint(x: -1910, y: -590), CGPoint(x: -5, y: 470), CGPoint(x: -900, y: 0)] {
            let frame = ShelfGeometry.frame(size: CGSize(width: 360, height: 400), near: point, in: bounds)
            #expect(bounds.contains(frame))
        }
    }

    @Test func smallScreensClampWindowSize() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        #expect(bounds.contains(ShelfGeometry.frame(size: CGSize(width: 360, height: 400), near: .zero, in: bounds)))
    }

    @Test func notchRequiresConsistentSafeGeometry() {
        let screen = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        #expect(ShelfGeometry.notch(frame: screen, topInset: 0, left: nil, right: nil) == nil)
        #expect(ShelfGeometry.notch(frame: screen, topInset: 32, left: .zero, right: .zero) == nil)
        let left = CGRect(x: -1512, y: 950, width: 650, height: 32)
        let right = CGRect(x: -650, y: 950, width: 650, height: 32)
        #expect(ShelfGeometry.notch(frame: screen, topInset: 32, left: left, right: right) == CGRect(x: -862, y: 950, width: 212, height: 32))
    }
}
