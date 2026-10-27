import Testing
import Foundation
@testable import OrganizeModule

private let now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10
private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

private func settings(_ rules: [OrganizeRule]) -> OrganizeSettings {
    var s = OrganizeSettings()
    s.isEnabled = true
    s.rules = rules
    return s
}

@Test func moduleOffPlansNothing() {
    var s = settings([OrganizeRule(name: "pdf", conditions: [.fileExtension(["pdf"])], actions: [.trash])])
    s.isEnabled = false
    #expect(RuleEngine.plan(for: FileFacts(name: "a.pdf", size: 1, addedAt: daysAgo(1)), settings: s, now: now).isEmpty)
}

@Test func disabledRuleIsSkipped() {
    let s = settings([OrganizeRule(name: "pdf", isEnabled: false, conditions: [.fileExtension(["pdf"])], actions: [.trash])])
    #expect(RuleEngine.plan(for: FileFacts(name: "a.pdf", size: 1, addedAt: daysAgo(1)), settings: s, now: now).isEmpty)
}

@Test func ignoresInProgressAndFreshDownloads() {
    let s = settings([OrganizeRule(name: "all", conditions: [.sizeGreaterThan(bytes: 0)], actions: [.trash])])
    #expect(RuleEngine.plan(for: FileFacts(name: "a.zip.crdownload", size: 9, addedAt: daysAgo(1)), settings: s, now: now).isEmpty)
    #expect(RuleEngine.plan(for: FileFacts(name: "a.zip", size: 9, addedAt: now.addingTimeInterval(-2)), settings: s, now: now).isEmpty)
}

@Test func installerPresetNeedsBothConditions() {
    var rule = OrganizePresets.installersToTrash
    rule.isEnabled = true
    let s = settings([rule])
    #expect(RuleEngine.plan(for: FileFacts(name: "App.dmg", size: 1, addedAt: daysAgo(3)), settings: s, now: now).isEmpty)
    #expect(RuleEngine.plan(for: FileFacts(name: "App.dmg", size: 1, addedAt: daysAgo(8)), settings: s, now: now).first?.actions == [.trash])
}

@Test func templatesAndDomainMatching() {
    let rule = OrganizeRule(
        name: "정부 문서",
        conditions: [.sourceDomain(["*.go.kr"]), .nameMatches(pattern: "*신청서*", isRegex: false)],
        actions: [.move(to: "~/Documents/{domain}/{yyyy}-{MM}"), .rename(template: "{yyyy}{MM}{dd}_{name}")]
    )
    let file = FileFacts(name: "지원금 신청서.hwp", size: 1, addedAt: daysAgo(1), sourceURLs: ["https://www.gov.go.kr/file/1"])
    let step = RuleEngine.plan(for: file, settings: settings([rule]), now: now).first
    let ym = RuleEngine.render("{yyyy}-{MM}", file, now: now)
    let ymd = RuleEngine.render("{yyyy}{MM}{dd}", file, now: now)
    #expect(step?.actions == [.move(to: "~/Documents/gov.go.kr/\(ym)"), .rename(template: "\(ymd)_지원금 신청서.hwp")])
}

@Test func anyModeNotAndStopAfterMatch() {
    let first = OrganizeRule(name: "이미지·영상", match: .any, conditions: [.kind([.image]), .kind([.video])],
                             actions: [.addTag("미디어")], stopAfterMatch: false)
    let second = OrganizeRule(name: "작은 파일 아님", conditions: [.not(.sizeLessThan(bytes: 1_000))], actions: [.notify])
    let steps = RuleEngine.plan(for: FileFacts(name: "clip.mp4", size: 5_000, addedAt: daysAgo(1)), settings: settings([first, second]), now: now)
    #expect(steps.map(\.ruleName) == ["이미지·영상", "작은 파일 아님"])
}

@Test func externalValuesCannotEscapePath() {
    let file = FileFacts(name: "..:etc.txt", size: 1, addedAt: daysAgo(1), sourceURLs: ["https://evil.com/x"])
    let rendered = RuleEngine.render("~/Downloads/{domain}/{name}", file, now: now)
    #expect(rendered == "~/Downloads/evil.com/__etc")
}

@Test func settingsRoundTripAsJSON() throws {
    let s = settings(OrganizePresets.all)
    let decoded = try JSONDecoder().decode(OrganizeSettings.self, from: JSONEncoder().encode(s))
    #expect(decoded == s)
}
