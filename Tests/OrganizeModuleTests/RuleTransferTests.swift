import Foundation
import Testing
@testable import OrganizeModule

private let sample = [
    OrganizeRule(name: "PDF", conditions: [.fileExtension(extensions: ["pdf"])], actions: [.move(to: "~/Documents/PDF")]),
    OrganizeRule(name: "오래된 설치 파일", isEnabled: false, conditions: [.kind(kinds: [.installer]), .addedMoreThan(days: 30)], actions: [.trash]),
]

@Test func exportImportRoundTripTurnsRulesOff() throws {
    let rules = try RuleTransfer.decode(try RuleTransfer.encode(sample))
    #expect(rules.map(\.name) == sample.map(\.name))
    #expect(rules.map(\.conditions) == sample.map(\.conditions))
    #expect(rules.map(\.actions) == sample.map(\.actions))
    #expect(rules.map(\.id) == sample.map(\.id))
    #expect(rules.allSatisfy { !$0.isEnabled })
}

@Test func exportHasFormatAndOnlyRules() throws {
    let json = try #require(try JSONSerialization.jsonObject(with: RuleTransfer.encode(sample)) as? [String: Any])
    #expect(json["format"] as? String == RuleTransfer.format)
    #expect(json["schemaVersion"] as? Int == OrganizeSettings.currentSchemaVersion)
    #expect(Set(json.keys) == ["format", "schemaVersion", "rules"])
}

@Test func importGivesNewIDsWhenTheyClash() throws {
    let data = try RuleTransfer.encode(sample)
    let rules = try RuleTransfer.decode(data, existingIDs: [sample[0].id])
    #expect(rules[0].id != sample[0].id)
    #expect(rules[1].id == sample[1].id)
    // 같은 파일 안에서 id가 겹쳐도 하나씩만
    let twice = try RuleTransfer.encode([sample[0], sample[0]])
    let decoded = try RuleTransfer.decode(twice)
    #expect(Set(decoded.map(\.id)).count == 2)
}

@Test func importReadsWholeSettingsFile() throws {
    var settings = OrganizeSettings()
    settings.rules = sample
    let rules = try RuleTransfer.decode(try JSONEncoder().encode(settings))
    #expect(rules.map(\.name) == sample.map(\.name))
}

@Test func importRejectsNewerSchema() throws {
    var json = try #require(try JSONSerialization.jsonObject(with: RuleTransfer.encode(sample)) as? [String: Any])
    json["schemaVersion"] = OrganizeSettings.currentSchemaVersion + 1
    #expect(throws: (any Error).self) { try RuleTransfer.decode(try JSONSerialization.data(withJSONObject: json)) }
}

@Test func importRejectsOtherFiles() {
    let bad: [String] = [
        "not json",
        #"{"name": "package", "version": "1.0"}"#,
        #"{"format": "something.else", "schemaVersion": 1, "rules": []}"#,
        #"{"schemaVersion": 1, "rules": [{"name": "x"}]}"#,
    ]
    for text in bad {
        #expect(throws: (any Error).self) { try RuleTransfer.decode(Data(text.utf8)) }
    }
    #expect(throws: (any Error).self) { try RuleTransfer.decode(Data(count: RuleTransfer.maxBytes + 1)) }
}
