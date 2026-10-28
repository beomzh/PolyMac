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
