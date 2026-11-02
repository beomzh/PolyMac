import AppKit
import Testing
@testable import CaptureModule

@Suite struct PinResizeTests {
    let base = NSSize(width: 200, height: 100)
    let start = NSRect(x: 100, y: 100, width: 200, height: 100)

    @Test func edgeBands() {
        let size = NSSize(width: 200, height: 100)
        #expect(PinResize.edges(at: NSPoint(x: 100, y: 50), in: size).isEmpty)
        #expect(PinResize.edges(at: NSPoint(x: 2, y: 50), in: size) == PinResize.Edges(left: true))
        #expect(PinResize.edges(at: NSPoint(x: 198, y: 98), in: size) == PinResize.Edges(right: true, top: true))
        // 작은 핀은 띠가 좁아져 가운데로 옮길 자리가 남는다
        #expect(PinResize.band(for: NSSize(width: 20, height: 20)) == 5)
    }

    @Test func rightEdgeKeepsLeftAndCenterY() {
        let (rect, factor) = PinResize.frame(from: start, base: base, edges: .init(right: true), dx: 200, dy: 0)
        #expect(factor == 2)
        #expect(rect == NSRect(x: 100, y: 50, width: 400, height: 200))
    }

    @Test func leftEdgeKeepsRight() {
        let (rect, _) = PinResize.frame(from: start, base: base, edges: .init(left: true), dx: 100, dy: 0)
        #expect(rect.maxX == start.maxX)
        #expect(rect.width == 100 && rect.height == 50)
    }

    @Test func bottomLeftCornerKeepsTopRight() {
        let (rect, factor) = PinResize.frame(from: start, base: base, edges: .init(left: true, bottom: true), dx: -20, dy: -100)
        #expect(factor == 2) // 세로로 더 많이 끌었다
        #expect(rect.maxX == start.maxX && rect.maxY == start.maxY)
        #expect(rect.size == NSSize(width: 400, height: 200))
    }

    @Test func clampsZoom() {
        let (small, f1) = PinResize.frame(from: start, base: base, edges: .init(right: true), dx: -500, dy: 0)
        #expect(f1 == PinResize.minZoom)
        #expect(small.width == base.width * PinResize.minZoom)
        let (_, f2) = PinResize.frame(from: start, base: base, edges: .init(top: true), dx: 0, dy: 10_000)
        #expect(f2 == PinResize.maxZoom)
    }
}
