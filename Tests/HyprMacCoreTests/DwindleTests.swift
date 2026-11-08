import CoreGraphics
import Testing
@testable import HyprMacCore

struct DwindleTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func singleWindowFillsScreen() {
        let t = DwindleTree()
        t.insert(1, splitting: nil, bounds: screen)
        #expect(t.layout(in: screen)[1] == screen)
    }

    @Test func dwindleSplitsAlongLongerSide() {
        let t = DwindleTree()
        t.insert(1, splitting: nil, bounds: screen)
        t.insert(2, splitting: 1, bounds: screen)      // wide → side by side
        t.insert(3, splitting: 2, bounds: screen)      // right half is tall → stacked
        let f = t.layout(in: screen)
        #expect(f[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(f[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
        #expect(t.windows == [1, 2, 3])
    }

    @Test func removeCollapsesParent() {
        let t = DwindleTree()
        [1, 2, 3].forEach { t.insert($0, splitting: $0 == 1 ? nil : $0 - 1, bounds: screen) }
        t.remove(2)
        let f = t.layout(in: screen)
        #expect(f[3] == CGRect(x: 500, y: 0, width: 500, height: 600))
        t.remove(1)
        #expect(t.layout(in: screen)[3] == screen)
        t.remove(3)
        #expect(t.isEmpty)
    }

    @Test func gaps() {
        let t = DwindleTree()
        t.insert(1, splitting: nil, bounds: screen)
        t.insert(2, splitting: 1, bounds: screen)
        let f = t.layout(in: screen, gapsIn: 5, gapsOut: 10)
        #expect(f[1]!.minX == 10)
        #expect(f[1]!.minY == 10)
        #expect(f[2]!.maxX == 990)
        #expect(f[2]!.minX - f[1]!.maxX == 10) // 2 × gaps_in between windows
    }

    @Test func swapToggleAndRatio() {
        let t = DwindleTree()
        t.insert(1, splitting: nil, bounds: screen)
        t.insert(2, splitting: 1, bounds: screen)
        t.swap(1, 2)
        #expect(t.layout(in: screen)[2]!.minX == 0)
        t.toggleSplit(1)
        #expect(t.layout(in: screen)[1] == CGRect(x: 0, y: 300, width: 1000, height: 300))
        t.adjustRatio(1, by: 0.1) // 1 is the second child → it grows
        #expect(t.layout(in: screen)[1]!.height == 360)
    }

    @Test func neighbor() {
        let left = CGRect(x: 0, y: 0, width: 500, height: 600)
        let topRight = CGRect(x: 500, y: 0, width: 500, height: 300)
        let bottomRight = CGRect(x: 500, y: 300, width: 500, height: 300)
        let all: [(Int, CGRect)] = [(1, left), (2, topRight), (3, bottomRight)]
        #expect(Geometry.neighbor(of: topRight, in: all.filter { $0.0 != 2 }, direction: .down) == 3)
        #expect(Geometry.neighbor(of: bottomRight, in: all.filter { $0.0 != 3 }, direction: .left) == 1)
        #expect(Geometry.neighbor(of: left, in: all.filter { $0.0 != 1 }, direction: .right) != nil)
        #expect(Geometry.neighbor(of: left, in: all.filter { $0.0 != 1 }, direction: .left) == nil)
    }
}
