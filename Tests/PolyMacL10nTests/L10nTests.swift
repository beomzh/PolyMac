import Testing
@testable import PolyMacL10n

/// 일본어·중국어 고르기. 전역 언어(L10n.override)는 다른 테스트와 겹칠 수 있어 언어를 직접 넘겨 확인한다.
@Suite struct L10nTests {
    @Test func systemLanguageMapsToSupportedLanguage() {
        #expect(L10n.matching(["ko-KR", "en-US"]) == .ko)
        #expect(L10n.matching(["ja-JP"]) == .ja)
        #expect(L10n.matching(["zh-Hans-CN"]) == .zhHans)
        #expect(L10n.matching(["zh-CN"]) == .zhHans)
        #expect(L10n.matching(["zh-Hant-TW"]) == .zhHant)
        #expect(L10n.matching(["zh-TW"]) == .zhHant)
        #expect(L10n.matching(["zh-HK"]) == .zhHant)
        #expect(L10n.matching(["fr-FR", "ko-KR"]) == .en)
        #expect(L10n.matching([]) == .en)
    }

    @Test func literalUsesCatalog() {
        #expect(L10n.translate("Save", to: .ja) == "保存")
        #expect(L10n.translate("Settings…", to: .zhHans) == "设置…")
        #expect(L10n.translate("Settings…", to: .zhHant) == "設定…")
    }

    @Test func interpolationFillsPlaceholders() {
        let n = 3
        let en: LString = "\(n) items"
        #expect(en.key == "{0} items")
        #expect(en.text == "3 items")
        #expect(L10n.translate(en, to: .ja) == "3 件")
        let w = 640, h = 480, size = "12 KB"
        #expect(L10n.translate("Image \(w) × \(h) px · \(size)", to: .zhHans) == "图像 640 × 480 像素 · 12 KB")
    }

    @Test func missingTranslationFallsBackToEnglish() {
        #expect(L10n.translate("Not in any catalog \(1)", to: .ja) == "Not in any catalog 1")
        #expect(L10n.translate("Save", to: .en) == "Save")
    }

    @Test func everyLanguageHasAName() {
        #expect(AppLanguage(rawValue: "zh-Hant") == .zhHant)
        #expect(AppLanguage.allCases.count == 6)
    }
}
