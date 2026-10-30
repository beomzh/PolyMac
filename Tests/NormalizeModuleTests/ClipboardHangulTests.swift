import AppKit
import Testing
@testable import NormalizeModule

private let nfd = "한글 파일.pdf".decomposedStringWithCanonicalMapping

private func scalars(_ s: String?) -> [UInt32] { s.map { $0.unicodeScalars.map(\.value) } ?? [] }

@Test func composeJoinsDecomposedHangul() throws {
    let fixed = try #require(HangulNormalizer.composeHangul(nfd))
    #expect(scalars(fixed) == scalars("한글 파일.pdf".precomposedStringWithCanonicalMapping))
}

@Test func composeJoinsPartlyDecomposedSyllable() throws {
    // 받침 없는 완성형 "하" + 끝소리 낱자 ㄴ
    let fixed = try #require(HangulNormalizer.composeHangul("하\u{11AB}"))
    #expect(scalars(fixed) == scalars("한"))
}

@Test func composeLeavesOtherTextAlone() {
    #expect(HangulNormalizer.composeHangul("이미 붙은 한글 abc") == nil)
    // 한자 호환 문자·옴 기호는 NFC라면 바뀌지만 여기서는 그대로
    #expect(HangulNormalizer.composeHangul("\u{F900}\u{2126}") == nil)
    // 옛한글 낱자(아래아 ᆞ)는 완성형이 없어 그대로
    #expect(HangulNormalizer.composeHangul("\u{1100}\u{119E}") == nil)
}

@MainActor
@Test func clipboardTextIsFixedButOtherTypesKept() throws {
    let pb = NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }
    pb.declareTypes([.string, .init("com.example.custom")], owner: nil)
    pb.setString(nfd, forType: .string)
    pb.setString("keep", forType: .init("com.example.custom"))
    let items = try #require(ClipboardHangulFix.fixedItems(pb))
    #expect(scalars(items.first?.string(forType: .string)) == scalars("한글 파일.pdf".precomposedStringWithCanonicalMapping))
    #expect(items.first?.string(forType: .init("com.example.custom")) == "keep")

    let fix = ClipboardHangulFix(pasteboard: pb)
    fix.start()
    pb.clearContents()
    pb.setString(nfd, forType: .string)
    fix.check()
    fix.stop()
    #expect(scalars(pb.string(forType: .string)) == scalars("한글 파일.pdf".precomposedStringWithCanonicalMapping))
}

@MainActor
@Test func clipboardSkipsPasswordsFilesAndPlainText() {
    let pb = NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }
    pb.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
    pb.setString(nfd, forType: .string)
    #expect(ClipboardHangulFix.fixedItems(pb) == nil)

    pb.clearContents()
    pb.writeObjects([URL(fileURLWithPath: "/tmp/\(nfd)") as NSURL])
    #expect(ClipboardHangulFix.fixedItems(pb) == nil)

    pb.clearContents()
    pb.setString("abc 한글", forType: .string)
    #expect(ClipboardHangulFix.fixedItems(pb) == nil)
}
