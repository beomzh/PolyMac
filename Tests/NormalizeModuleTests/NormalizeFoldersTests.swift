import Foundation
import Testing
@testable import NormalizeModule

private func store() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "normalize-folders-\(UUID().uuidString)"))
}

@Test func defaultsAndLegacyExtraFolders() throws {
    let s = try store()
    #expect(NormalizeFolders.load(from: s).map(\.path) == ["~/Downloads", "~/Desktop"])
    s.set(["~/Documents/받은파일", "~/Downloads"], forKey: "normalize.extraFolders")
    // 예전 "추가 폴더"를 이어받고 중복은 하나로
    #expect(NormalizeFolders.load(from: s).map(\.path) == ["~/Downloads", "~/Desktop", "~/Documents/받은파일"])
}

@Test func saveRemovesDefaultsAndKeepsDisabled() throws {
    let s = try store()
    s.set(["~/Old"], forKey: "normalize.extraFolders")
    NormalizeFolders.save([.init(path: "~/Documents"), .init(path: "~/Desktop", isEnabled: false)], to: s)
    let loaded = NormalizeFolders.load(from: s)
    #expect(loaded == [.init(path: "~/Documents"), .init(path: "~/Desktop", isEnabled: false)])
    #expect(s.object(forKey: "normalize.extraFolders") == nil)
    NormalizeFolders.save([], to: s)
    #expect(NormalizeFolders.load(from: s).isEmpty) // 빈 목록도 그대로 (기본값으로 되돌아가지 않음)
}

@Test func onlyRealFoldersInsideHomeOutsideLibrary() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let docs = home.appendingPathComponent("Documents"), lib = home.appendingPathComponent("Library/Caches")
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(NormalizeFolders.problem(with: docs.path, home: home.path) == nil)
    #expect(NormalizeFolders.problem(with: home.path, home: home.path) != nil)
    #expect(NormalizeFolders.problem(with: lib.path, home: home.path) != nil)
    #expect(NormalizeFolders.problem(with: "/Applications", home: home.path) != nil)
    #expect(NormalizeFolders.problem(with: home.appendingPathComponent("없음").path, home: home.path) != nil)
}
