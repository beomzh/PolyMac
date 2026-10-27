import Testing
import Foundation
@testable import NormalizeModule

@Test func detectsDecomposedHangul() {
    let nfd = "한글".decomposedStringWithCanonicalMapping
    #expect(nfd == "한글") // Swift ==는 정규화 차이를 무시한다 — 그래서 needsNFC가 필요
    #expect(HangulNormalizer.needsNFC(nfd))
    #expect(!HangulNormalizer.needsNFC("한글"))
    #expect(!HangulNormalizer.needsNFC("english.txt"))
}

@Test func normalizesDirectoryOnceAndIsIdempotent() throws {
    let dir = NSTemporaryDirectory() + "polymac-nfc-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    FileManager.default.createFile(atPath: dir + "/" + "회의록.txt".decomposedStringWithCanonicalMapping, contents: nil)

    #expect(try HangulNormalizer.normalizeDirectory(dir).count == 1)
    #expect(try HangulNormalizer.normalizeDirectory(dir).isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir)
    #expect(names.allSatisfy { !HangulNormalizer.needsNFC($0) })
}
