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
