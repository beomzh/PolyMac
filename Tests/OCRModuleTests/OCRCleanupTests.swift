import CoreGraphics
import Testing
@testable import OCRModule

@Test func middleBulletBecomesInterpunct() {
    #expect(OCRCleanup.apply("알림 보이기 • 위치: 오른쪽 위") == "알림 보이기 · 위치: 오른쪽 위")
    #expect(OCRCleanup.apply("Apple Silicon•Intel") == "Apple Silicon·Intel")
}

@Test func leadingBulletStaysABullet() {
    #expect(OCRCleanup.apply("• 첫 항목 • 설명\n  • 둘째") == "• 첫 항목 · 설명\n  • 둘째")
}

@Test func threeDotsBecomeEllipsisButPeriodsStay() {
    #expect(OCRCleanup.apply("가운뎃점•·• 말줄임") == "가운뎃점… 말줄임")
    #expect(OCRCleanup.apply("가운뎃점••• 말줄임") == "가운뎃점… 말줄임")
    #expect(OCRCleanup.apply("for i in 0...9") == "for i in 0...9") // 코드의 마침표 셋은 그대로
}

@Test func upscaleDoublesSmallImagesOnly() throws {
    let ctx = try #require(CGContext(data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(ctx.makeImage())
    let big = TextRecognizer.scaled(image, by: 2)
    #expect(big.width == 80 && big.height == 20)
    #expect(TextRecognizer.scaled(image, by: 1).width == 40)
    // 앱 기본값: 한국어 먼저, 2배, 2 MP 넘으면 그대로
    let options = OCROptions()
    #expect(options.languages.first == "ko-KR")
    #expect(options.upscale == 2 && options.upscaleMaxPixels == 2_000_000 && options.cleanup)
}

/// 한 줄로 이어도 각 줄 맨 앞 글머리표는 글머리표로 남는다 (정리를 잇기 전에 하므로)
@Test func bulletsSurviveSingleLineJoin() {
    let lines = ["• 첫 항목", "• 둘째 • 설명"].enumerated().map { i, text in
        LineJoiner.Line(text: OCRCleanup.fixLine(text), box: CGRect(x: 0.1, y: 0.8 - Double(i) * 0.1, width: 0.5, height: 0.05))
    }
    #expect(LineJoiner.join(lines, mode: .singleLine) == "• 첫 항목 • 둘째 · 설명")
}
