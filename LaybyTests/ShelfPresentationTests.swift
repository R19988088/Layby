import Foundation
import Testing
@testable import LaybyKit

struct ShelfPresentationTests {
    @Test func expansionKeepsTopCenterWhenSpaceAllows() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let original = CGRect(x: 400, y: 400, width: 360, height: 380)
        let expanded = ShelfGeometry.resizedFrame(original, size: CGSize(width: 660, height: 480), in: bounds)
        #expect(expanded.midX == original.midX)
        #expect(expanded.maxY == original.maxY)
        let compact = ShelfGeometry.resizedFrame(expanded, size: original.size, in: bounds)
        #expect(compact == original)
    }

    @Test func expansionClampsToNegativeCoordinateAndSmallDisplays() {
        for bounds in [CGRect(x: -1440, y: -200, width: 1440, height: 900),
                       CGRect(x: 0, y: 0, width: 500, height: 350)] {
            let original = CGRect(x: bounds.minX, y: bounds.minY, width: 360, height: 380)
            let expanded = ShelfGeometry.resizedFrame(original, size: CGSize(width: 660, height: 480), in: bounds)
            #expect(bounds.contains(expanded))
        }
    }
}
