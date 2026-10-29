import Foundation
import Testing
@testable import ClipboardModule

/// 이미지 기능 이전에 저장된 기록(이미지 필드 없음)도 그대로 읽혀야 한다.
@Test func decodesHistoryWithoutImageFields() throws {
    let old = #"[{"id":"6F1C2A4E-0000-4000-8000-000000000001","text":"안녕","sourceApp":"com.apple.Terminal","copiedAt":"2026-10-27T05:00:00Z","isPinned":true}]"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let items = try decoder.decode([ClipboardItem].self, from: Data(old.utf8))
    #expect(items.count == 1)
    #expect(items[0].text == "안녕")
    #expect(items[0].isPinned)
    #expect(!items[0].isImage)
}

@Test func imageItemRoundTrips() throws {
    let item = ClipboardItem.image(file: "a.png", width: 10, height: 20, bytes: 300, hash: "abc", sourceApp: nil)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let back = try decoder.decode(ClipboardItem.self, from: encoder.encode(item))
    #expect(back.isImage)
    #expect(back.imageWidth == 10 && back.imageHeight == 20)
}

@Test func concealedTypesAreIgnored() {
    #expect(ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], frontmostBundleID: nil))
    #expect(ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], frontmostBundleID: "com.bitwarden.desktop"))
    #expect(!ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], frontmostBundleID: "com.apple.Terminal"))
}

@Test func filesKeepPathsAndExcludedAppsAreSkipped() throws {
    let item = ClipboardItem.files(["/tmp/a.txt", "/tmp/b 폴더"], sourceApp: "com.apple.finder")
    #expect(item.isFiles && !item.isImage && item.storedFiles.isEmpty) // 파일 내용은 따로 저장하지 않는다
    let back = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(item))
    #expect(back.files == ["/tmp/a.txt", "/tmp/b 폴더"])
    #expect(back.text.contains("b 폴더")) // 검색용

    #expect(ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], frontmostBundleID: "com.tinyspeck.slackmacgap",
                                          excludedApps: ["com.tinyspeck.slackmacgap"]))
    #expect(!ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], frontmostBundleID: "com.apple.Safari",
                                           excludedApps: ["com.tinyspeck.slackmacgap"]))
}

@Test func richTextKeepsPlainTextAndStoresRTFFile() throws {
    var item = ClipboardItem.richText("굵은 글자", file: "r.rich", hash: "h", sourceApp: "com.apple.Safari")
    item.origin = "ocr"
    #expect(item.isRich && !item.isImage && !item.isLargeText)
    #expect(item.text == "굵은 글자") // 서식 없이 붙여넣기에 쓴다
    #expect(item.storedFiles == ["clipboard-rich/r.rich"]) // 지울 때 같이 지운다
    let back = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(item))
    #expect(back.richFile == "r.rich")
    #expect(back.originKind == .ocr)
}

/// 새 버전이 모르는 출처 값을 남겨도 기록 전체가 깨지지 않는다
@Test func unknownOriginIsIgnored() throws {
    let json = #"{"id":"6F1C2A4E-0000-4000-8000-000000000002","text":"x","copiedAt":0,"isPinned":false,"origin":"somethingNew"}"#
    let item = try JSONDecoder().decode(ClipboardItem.self, from: Data(json.utf8))
    #expect(item.origin == "somethingNew")
    #expect(item.originKind == nil)
    #expect(!item.isRich)
}

/// Chrome은 HTML만 넣는다 — 링크가 든 글도 서식이 남아야 한다
@Test func richFormatsKeepHTMLAndRTFRoundTrip() throws {
    let html = Data(#"<a href="https://example.com">예시</a>"#.utf8)
    let rtf = Data(#"{\rtf1 x}"#.utf8)
    let data = try #require(RichFormats.encode(["public.html": html, "public.rtf": rtf, "public.utf8-plain-text": Data("x".utf8)]))
    let back = RichFormats.decode(data, file: "a.rich")
    #expect(back == ["public.html": html, "public.rtf": rtf]) // 글자는 item.text에 따로
    #expect(RichFormats.decode(rtf, file: "old.rtf") == ["public.rtf": rtf]) // 예전 파일
    #expect(RichFormats.decode(Data("garbage".utf8), file: "b.rich").isEmpty)
}

@Test func richFormatsSkipEmptyAndOversized() {
    #expect(RichFormats.encode([:]) == nil)
    #expect(RichFormats.encode(["public.html": Data()]) == nil)
    #expect(RichFormats.encode(["public.html": Data(count: RichFormats.maxBytes + 1)]) == nil)
}
