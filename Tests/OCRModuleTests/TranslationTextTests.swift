import Testing
@testable import OCRModule

@Suite struct TranslationTextTests {
    @Test func keepsLinesBlankLinesAndIndent() {
        let text = "First line\n\n  - item one\n  - item two\n    indented\n}\n\nLast"
        let blocks = TranslationText.blocks(text)
        #expect(blocks.map(\.body) == ["First line", "", "item one", "item two", "indented", "", "", "Last"])
        #expect(TranslationText.rebuild(blocks, translated: [:]) == text)
    }

    @Test func rebuildUsesTranslationAndKeepsMarkers() {
        let blocks = TranslationText.blocks("Steps:\n1. Open\n2. Press")
        let out = TranslationText.rebuild(blocks, translated: [0: "단계:", 1: "열기", 2: "누르기\n\n"])
        #expect(out == "단계:\n1. 열기\n2. 누르기")
    }

    @Test func joinsSentenceBrokenByWidth() {
        let blocks = TranslationText.blocks("This is a sentence that was broken\nacross two lines and contin-\nues here.\nNext Line")
        #expect(blocks.map(\.body) == ["This is a sentence that was broken across two lines and continues here.", "Next Line"])
    }

    @Test func listsAndHeadingsStaySeparate() {
        #expect(TranslationText.blocks("Menu One\nMenu Two").count == 2)
        #expect(TranslationText.blocks("Done.\nnext one").count == 2)
        #expect(TranslationText.blocks("Intro\n- lower item").count == 2)
    }

    @Test func windowsLineEndings() {
        #expect(TranslationText.blocks("A one\r\nB two").count == 2)
    }

    @Test func splitsMarkers() {
        #expect(TranslationText.split("  • 항목").prefix == "  • ")
        #expect(TranslationText.split("10) 열번째").body == "열번째")
        #expect(TranslationText.split("3.14 is pi").prefix == "")
    }
}
