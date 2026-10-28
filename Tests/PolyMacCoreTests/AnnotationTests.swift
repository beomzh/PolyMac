import AppKit
import Testing
@testable import PolyMacCore

/// 칸마다 색이 다른 100×100 그림 (모자이크 전후를 구분하려고)
private func noiseImage() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<100 { for y in 0..<100 {
        ctx.setFillColor(CGColor(red: CGFloat((x * 7 + y * 13) % 255) / 255, green: CGFloat((x * y) % 255) / 255, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
    } }
    return ctx.makeImage()!
}

private func pixels(_ image: CGImage) -> [UInt8] {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
}

private func pixel(_ data: [UInt8], _ x: Int, _ yFromTop: Int) -> [UInt8] {
    let i = (yFromTop * 100 + x) * 4
    return Array(data[i..<i + 4])
}

@Test @MainActor func mosaicMakesBlocksAndLeavesTheRest() {
    let image = noiseImage()
    var mosaic = Annotation(tool: .mosaic, start: CGPoint(x: 0, y: 50), color: .red) // 위쪽 절반 (왼쪽 아래 기준 y 50~100)
    mosaic.extend(to: CGPoint(x: 100, y: 100))
    #expect(mosaic.isMeaningful)
    let before = pixels(image)
    let after = pixels(AnnotationRenderer.composite(image, scale: 1, annotations: [mosaic]))
    // 가린 곳: 한 칸(10pt) 안의 이웃 픽셀이 같은 색
    #expect(pixel(after, 1, 1) == pixel(after, 2, 2))
    #expect(pixel(before, 1, 1) != pixel(before, 2, 2))
    // 안 가린 아래쪽은 그대로
    #expect(pixel(after, 33, 77) == pixel(before, 33, 77))
}

@Test @MainActor func numbersCountUpAndTextNeedsContent() {
    var one = Annotation(tool: .number, start: CGPoint(x: 20, y: 20), color: .systemBlue)
    one.number = Annotation.nextNumber(after: [])
    var two = Annotation(tool: .number, start: CGPoint(x: 60, y: 60), color: .systemBlue)
    two.number = Annotation.nextNumber(after: [one])
    #expect(one.number == 1 && two.number == 2 && one.isMeaningful)

    var text = Annotation(tool: .text, start: CGPoint(x: 5, y: 90), color: .systemRed)
    #expect(!text.isMeaningful)
    text.text = "확인"
    #expect(text.isMeaningful)
    // 실제로 그림이 바뀐다
    let image = noiseImage()
    #expect(pixels(AnnotationRenderer.composite(image, scale: 1, annotations: [one, two, text])) != pixels(image))
}

/// 두 번째 이후 번호도 자기 동그라미 안에 숫자가 그려진다 (앞 표시의 글자 위치에 끌려가지 않게)
@Test @MainActor func everyNumberIsDrawnInsideItsCircle() {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(.black)
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    let black = ctx.makeImage()!
    var marks: [Annotation] = []
    for center in [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 50), CGPoint(x: 80, y: 80)] {
        var mark = Annotation(tool: .number, start: center, color: NSColor(srgbRed: 0, green: 0, blue: 0.6, alpha: 1))
        mark.number = Annotation.nextNumber(after: marks)
        marks.append(mark)
    }
    let data = pixels(AnnotationRenderer.composite(black, scale: 1, annotations: marks))
    for mark in marks {
        let cx = Int(mark.points[0].x), cyFromTop = 100 - Int(mark.points[0].y)
        // 테두리(반지름 12~14)를 뺀 안쪽에 흰 글자 픽셀이 있어야 한다
        let hasDigit = (-7...7).contains { dx in (-7...7).contains { dy in pixel(data, cx + dx, cyFromTop + dy)[0] > 180 } }
        #expect(hasDigit, "number \(mark.number ?? 0) is not inside its circle")
    }
}
