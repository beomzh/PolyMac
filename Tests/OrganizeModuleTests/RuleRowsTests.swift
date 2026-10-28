import Foundation
import Testing
@testable import OrganizeModule

@Test func conditionRowsRoundTrip() {
    let conditions: [Condition] = [
        .fileExtension(extensions: ["pdf", "hwp"]),
        .kind(kinds: [.image, .video]),
        .nameMatches(pattern: "*견적서*", isRegex: false),
        .sourceDomain(domains: ["go.kr"]),
        .sizeGreaterThan(bytes: 5_000_000),
        .addedMoreThan(days: 7),
        .not(condition: .kind(kinds: [.installer])),
        .isDuplicate,
    ]
    #expect(conditions.map { ConditionRow($0).condition } == conditions)
}

@Test func conditionRowCleansInputAndDropsEmpty() {
    var row = ConditionRow(kind: .fileExtension)
    #expect(row.condition == nil)
    row.text = " .PDF , zip,"
    #expect(row.condition == .fileExtension(extensions: ["pdf", "zip"]))
    row.kind = .kind
    #expect(row.condition == nil) // 종류를 하나도 안 고름
}

@Test func actionRowsRoundTrip() {
    let actions: [Action] = [.move(to: "~/Documents/{yyyy}"), .copy(to: "~/Backup"), .rename(template: "{name}.{ext}"), .trash, .addTag(name: "빨간색"), .notify]
    #expect(actions.map { ActionRow($0).action } == actions)
    #expect(ActionRow(kind: .move, text: "  ").action == nil)
}

@Test func duplicateNames() {
    #expect(DuplicateName.original(of: "보고서 (1).pdf") == "보고서.pdf")
    #expect(DuplicateName.original(of: "보고서 2.pdf") == "보고서.pdf")
    #expect(DuplicateName.original(of: "archive (12)") == "archive")
    #expect(DuplicateName.original(of: "보고서.pdf") == nil)
    #expect(DuplicateName.original(of: "2024.pdf") == nil)
    #expect(DuplicateName.original(of: " (1).pdf") == nil)
}

@MainActor @Test func duplicateNeedsSameContent() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("같은 내용".utf8).write(to: dir.appendingPathComponent("a.txt"))
    try Data("같은 내용".utf8).write(to: dir.appendingPathComponent("a (1).txt"))
    try Data("다른 내용".utf8).write(to: dir.appendingPathComponent("a 2.txt"))
    let same = dir.appendingPathComponent("a (1).txt").path, different = dir.appendingPathComponent("a 2.txt").path
    #expect(OrganizeModule.facts(path: same, name: "a (1).txt").isDuplicate)
    #expect(!OrganizeModule.facts(path: different, name: "a 2.txt").isDuplicate)
}
