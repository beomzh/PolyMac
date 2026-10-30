import Foundation
import Testing
@testable import OrganizeModule

@Test func openPartialFindsUnclosedBrace() {
    #expect(TemplateTokens.openPartial(in: "사진_{ya") == "ya")
    #expect(TemplateTokens.openPartial(in: "사진_{") == "")
    #expect(TemplateTokens.openPartial(in: "{name}_") == nil)
    #expect(TemplateTokens.openPartial(in: "a{b c") == nil)
}

@Test func suggestionsNarrowWhileTyping() {
    #expect(TemplateTokens.suggestions(for: "{n").map(\.text) == ["{name}"])
    #expect(TemplateTokens.suggestions(for: "{m").map(\.text) == ["{MM}"])
    #expect(TemplateTokens.suggestions(for: "x").count == TemplateTokens.all.count)
    #expect(TemplateTokens.suggestions(for: "{zz").isEmpty)
}

@Test func insertCompletesOrAppends() {
    let name = TemplateTokens.all.first { $0.text == "{name}" }!
    #expect(TemplateTokens.insert(name, into: "{yyyy}_{na") == "{yyyy}_{name}")
    #expect(TemplateTokens.insert(name, into: "{yyyy}_") == "{yyyy}_{name}")
}

@Test func unknownTokensAreReportedOnce() {
    #expect(TemplateTokens.unknown(in: "{date}_{name}_{date}{Name}") == ["{date}", "{Name}"])
    #expect(TemplateTokens.unknown(in: "{yyyy}{MM}{dd}_{name}.{ext}").isEmpty)
}

@Test func previewMatchesRealRename() {
    var c = DateComponents()
    c.year = 2026; c.month = 10; c.day = 30
    let now = Calendar.current.date(from: c)!
    let name = TemplateTokens.preview("{yyyy}{MM}{dd}_{name}", rename: true, now: now)
    #expect(name.hasPrefix("20261030_"))
    #expect(name.hasSuffix(".pdf"))
    #expect(TemplateTokens.preview("~/Documents/{domain}", rename: false, now: now) == "~/Documents/example.com")
}
