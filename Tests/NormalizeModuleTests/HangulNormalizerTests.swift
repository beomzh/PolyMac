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

@Test func skipsHiddenAndInProgressDownloads() throws {
    let dir = NSTemporaryDirectory() + "polymac-nfc-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let downloading = "보고서.pdf.crdownload".decomposedStringWithCanonicalMapping
    let hidden = ".임시".decomposedStringWithCanonicalMapping
    FileManager.default.createFile(atPath: dir + "/" + downloading, contents: nil)
    FileManager.default.createFile(atPath: dir + "/" + hidden, contents: nil)

    #expect(try HangulNormalizer.normalizeDirectory(dir).isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir)
    #expect(names.allSatisfy { HangulNormalizer.needsNFC($0) }) // 그대로 NFD
}

@Test func normalizesWholeTreeButNotInsidePackages() throws {
    let root = NSTemporaryDirectory() + "polymac-tree-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: root) }
    let nfd = { (s: String) in s.decomposedStringWithCanonicalMapping }
    let top = root + "/" + nfd("자료")
    try FileManager.default.createDirectory(atPath: top + "/" + nfd("하위") + "/" + nfd("깊은"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: top + "/" + nfd("하위") + "/" + nfd("문서.txt"), contents: nil)
    try FileManager.default.createDirectory(atPath: top + "/Tool.app/" + nfd("내부"), withIntermediateDirectories: true)

    let url = URL(fileURLWithPath: top)
    #expect(HangulNormalizer.countTree(url) == 4) // 자료, 하위, 깊은, 문서.txt (앱 안은 제외)
    let renamed = try HangulNormalizer.normalizeTree(url)
    #expect(renamed.count == 4)
    let names = try FileManager.default.subpathsOfDirectory(atPath: root)
    #expect(names.contains("자료/하위/문서.txt".precomposedStringWithCanonicalMapping))
    // 앱 패키지 안은 그대로
    #expect(try FileManager.default.contentsOfDirectory(atPath: root + "/자료/Tool.app").allSatisfy(HangulNormalizer.needsNFC))
    #expect(HangulNormalizer.countTree(url) == 0)
}

@Test func windowsZipMarksNamesAsUTF8AndSkipsMacJunk() throws {
    let root = NSTemporaryDirectory() + "polymac-zip-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: root) }
    let folder = root + "/" + "보고서".decomposedStringWithCanonicalMapping
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try Data(String(repeating: "가나다 ", count: 2000).utf8).write(to: URL(fileURLWithPath: folder + "/" + "본문.txt".decomposedStringWithCanonicalMapping))
    FileManager.default.createFile(atPath: folder + "/.DS_Store", contents: Data([1, 2, 3]))
    let zip = URL(fileURLWithPath: root + "/out.zip")

    #expect(try WindowsZip.create(from: [URL(fileURLWithPath: folder)], to: zip) == 1)
    let bytes = try Data(contentsOf: zip)
    #expect(bytes[6] & 0x08 == 0x08 || bytes[7] & 0x08 == 0x08) // 플래그 11번(UTF-8 이름)
    #expect(bytes.range(of: Data("보고서/본문.txt".precomposedStringWithCanonicalMapping.utf8)) != nil)
    #expect(bytes.range(of: Data(".DS_Store".utf8)) == nil)

    // macOS ditto로 풀어 내용이 같은지(CRC·압축) 확인
    let out = root + "/unzipped"
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    unzip.arguments = ["-x", "-k", zip.path, out]
    try unzip.run()
    unzip.waitUntilExit()
    #expect(unzip.terminationStatus == 0)
    let restored = try String(contentsOfFile: out + "/보고서/본문.txt".precomposedStringWithCanonicalMapping, encoding: .utf8)
    #expect(restored == String(repeating: "가나다 ", count: 2000))
}
