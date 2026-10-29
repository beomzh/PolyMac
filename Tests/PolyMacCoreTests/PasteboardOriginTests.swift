import AppKit
import Testing
@testable import PolyMacCore

/// 출처 표식은 글자와 함께 들어가고, 붙여넣을 글자는 그대로
@Test @MainActor func copyMarksOriginAndKeepsText() {
    let pb = NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }
    PasteboardWriter.copy("hello", origin: .paths, to: pb)
    #expect(pb.string(forType: .string) == "hello")
    #expect(pb.string(forType: PasteboardOrigin.type) == "paths")
    PasteboardWriter.copy("plain", to: pb)
    #expect(pb.string(forType: PasteboardOrigin.type) == nil)
}

@Test func originRawValuesAreStable() {
    // 기록 파일에 저장되는 값 — 바꾸면 예전 기록의 태그가 사라진다
    #expect(PasteboardOrigin.allCases.map(\.rawValue) == ["ocr", "capture", "paths", "color"])
}
