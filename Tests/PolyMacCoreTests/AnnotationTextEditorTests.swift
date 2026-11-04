import AppKit
import Testing
@testable import PolyMacCore

private func textMark(_ text: String = "확인", at top: CGPoint = CGPoint(x: 50, y: 100)) -> Annotation {
    var mark = Annotation(tool: .text, start: top, color: .systemRed)
    mark.text = text
    return mark
}

@MainActor
private final class Host {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    var marks: [Annotation]
    lazy var editor = AnnotationTextEditor(view: view, get: { [unowned self] in marks }, set: { [unowned self] in marks = $0 }, toView: { NSPoint(x: $0.x, y: $0.y) })
    init(_ marks: [Annotation]) { self.marks = marks }
}

@Test func clickPointIsMiddleOfFirstLine() {
    let top = Annotation.textOrigin(click: CGPoint(x: 10, y: 50), fontSize: 20)
    #expect(top.x == 10)
    #expect(top.y == 50 + AnnotationRenderer.lineHeight(20) / 2)
}

@Test func boundsFollowFontSizeAndLines() {
    var mark = textMark("한 줄\n두 줄")
    let one = AnnotationRenderer.textBounds(mark)
    #expect(one.maxY == 100)
    #expect(one.height == AnnotationRenderer.lineHeight(20) * 2)
    mark.fontSize = 40
    #expect(AnnotationRenderer.textBounds(mark).width > one.width * 1.8)
}

@Test func resizeKeepsOppositeCorner() {
    let mark = textMark()
    let box = AnnotationRenderer.textBounds(mark)
    let big = mark.textResized(from: .bottomRight, to: CGPoint(x: box.minX + box.width * 2, y: box.maxY - box.height * 2))
    #expect(big.fontSize == 40)
    #expect(big.points[0] == mark.points[0])
    let left = mark.textResized(from: .topLeft, to: CGPoint(x: box.maxX - box.width * 2, y: box.minY + box.height * 2))
    let after = AnnotationRenderer.textBounds(left)
    #expect(abs(after.maxX - box.maxX) < 2)
    #expect(abs(after.minY - box.minY) < 2)
}

@Test func resizeStaysInRange() {
    let mark = textMark()
    let box = AnnotationRenderer.textBounds(mark)
    #expect(mark.textResized(from: .bottomRight, to: CGPoint(x: box.minX, y: box.maxY)).fontSize == 10)
    #expect(mark.textResized(from: .bottomRight, to: CGPoint(x: 100_000, y: -100_000)).fontSize == 160)
}

@MainActor @Test func dragMovesAndUndoRestores() {
    let host = Host([textMark()])
    let inside = CGPoint(x: 55, y: 90)
    #expect(host.editor.press(at: inside, clickCount: 1) == .grabbed)
    host.editor.dragged(to: CGPoint(x: 85, y: 70))
    host.editor.released()
    #expect(host.marks[0].points[0] == CGPoint(x: 80, y: 80))
    #expect(host.editor.undo())
    #expect(host.marks[0].points[0] == CGPoint(x: 50, y: 100))
    #expect(!host.editor.undo())
}

@MainActor @Test func clickWithoutDragLeavesNoUndoStep() {
    let host = Host([textMark()])
    _ = host.editor.press(at: CGPoint(x: 55, y: 90), clickCount: 1)
    host.editor.released()
    #expect(host.editor.selected == 0)
    #expect(!host.editor.undo())
}

@MainActor @Test func cornerResizesSelectedText() {
    let host = Host([textMark()])
    _ = host.editor.press(at: CGPoint(x: 55, y: 90), clickCount: 1)
    host.editor.released()
    let box = AnnotationRenderer.textBounds(host.marks[0])
    #expect(host.editor.press(at: CGPoint(x: box.maxX, y: box.minY), clickCount: 1) == .grabbed)
    host.editor.dragged(to: CGPoint(x: box.minX + box.width * 3, y: box.maxY - box.height * 3))
    host.editor.released()
    #expect(host.marks[0].fontSize == 60)
}

@MainActor @Test func selectDeleteAndMiss() {
    let host = Host([textMark(), textMark("위", at: CGPoint(x: 50, y: 100))])
    #expect(host.editor.press(at: CGPoint(x: 55, y: 90), clickCount: 1) == .grabbed)
    host.editor.released()
    #expect(host.editor.selected == 1) // 겹치면 맨 위
    #expect(host.editor.press(at: CGPoint(x: 55, y: 90), clickCount: 2) == .edit)
    host.editor.released()
    #expect(host.editor.deleteSelected())
    #expect(host.marks.count == 1)
    #expect(host.editor.press(at: CGPoint(x: 300, y: 250), clickCount: 1) == .none)
    #expect(host.editor.selected == nil)
    #expect(!host.editor.deleteSelected())
}

/// 입력 칸에 보이는 글자와 확정해서 그린 글자가 같은 자리에 있다
@MainActor @Test func inputLinesUpWithFinalText() throws {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.backgroundColor = .black
    window.contentView = view
    let top = NSPoint(x: 40, y: 80)
    let input = AnnotationTextInput(in: view, at: top, text: "Hg글", color: .white, fontSize: 20, zoom: 1) { _ in }
    let box = try #require(textInk(view) { field in field.layer?.borderWidth = 0 })
    var mark = Annotation(tool: .text, start: top, color: .white)
    mark.text = "Hg글"
    let context = try #require(CGContext(data: nil, width: 300, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 300, height: 120))
    AnnotationRenderer.draw([mark], in: context)
    let rep = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    let final = try #require(inkBox(rep))
    print("input ink \(box), final ink \(final)")
    #expect(abs(box.minX - final.minX) <= 1.5)
    #expect(abs(box.minY - final.minY) <= 1.5)
    #expect(abs(box.maxY - final.maxY) <= 1.5)
    input.commit()
}

@MainActor private func textInk(_ view: NSView, prepare: (NSTextView) -> Void) -> CGRect? {
    guard let field = view.subviews.compactMap({ $0 as? NSTextView }).first else { return nil }
    prepare(field)
    view.subviews.filter { $0 !== field }.forEach { $0.isHidden = true }
    field.setSelectedRange(NSRange(location: 0, length: 0))
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return inkBox(rep)
}

/// 밝은 픽셀의 영역 (표시 좌표, 왼쪽 아래 원점, 포인트)
private func inkBox(_ rep: NSBitmapImageRep) -> CGRect? {
    let factor = CGFloat(rep.pixelsWide) / rep.size.width
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5, c.brightnessComponent > 0.6 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: CGFloat(minX) / factor, y: rep.size.height - CGFloat(maxY + 1) / factor,
                  width: CGFloat(maxX - minX + 1) / factor, height: CGFloat(maxY - minY + 1) / factor)
}
