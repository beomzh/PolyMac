import Foundation
import Testing
@testable import PolyMacCore

/// 기록 파일이 한도를 넘으면 `.1`로 넘어가고, 그전 `.1`은 하나만 남는다
@Test func logRotatesAtLimitAndKeepsOnePrevious() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("polymac-log-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("organize-log.txt")
    let previous = dir.appendingPathComponent("organize-log.1.txt")
    let read = { (url: URL) in (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    AppPaths.appendLine("first", to: log, rotateAt: 10)
    #expect(read(log) == "first\n" && !FileManager.default.fileExists(atPath: previous.path))
    AppPaths.appendLine("second", to: log, rotateAt: 10)   // 6바이트라 아직 그대로
    #expect(read(log) == "first\nsecond\n")
    AppPaths.appendLine("third", to: log, rotateAt: 10)    // 13바이트 → 넘김
    #expect(read(previous) == "first\nsecond\n" && read(log) == "third\n")
    AppPaths.appendLine("fourth-long", to: log, rotateAt: 10)
    AppPaths.appendLine("fifth", to: log, rotateAt: 10)    // 그전 .1은 지워지고 하나만
    #expect(read(previous) == "third\nfourth-long\n" && read(log) == "fifth\n")
    let mode = try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}
