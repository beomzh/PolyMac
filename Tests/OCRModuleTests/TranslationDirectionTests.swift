import Testing
@testable import OCRModule

@Suite struct TranslationDirectionTests {
    @Test func detectsLanguage() {
        #expect(TranslationDirection.source(of: "이 문서는 화면의 글자를 읽어 클립보드에 복사하는 방법을 설명합니다.") == "ko")
        #expect(TranslationDirection.source(of: "This document explains how to read text on the screen and copy it.") == "en")
    }

    @Test func emptyFallsBack() {
        #expect(TranslationDirection.source(of: "12345") == "en")
    }

    @Test func foreignTextGoesToMyLanguage() {
        #expect(TranslationDirection.target(source: "en", preferred: "ko") == "ko")
        #expect(TranslationDirection.target(source: "ja", preferred: "ko") == "ko")
    }

    @Test func myLanguageGoesToEnglish() {
        #expect(TranslationDirection.target(source: "ko", preferred: "ko") == "en")
        #expect(TranslationDirection.target(source: "en", preferred: "en") == "ko")
        #expect(TranslationDirection.target(source: "ko", preferred: "ko-KR") == "en")
    }
}
