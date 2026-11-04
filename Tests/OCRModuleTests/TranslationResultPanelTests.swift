import AppKit
import Testing
@testable import OCRModule

@MainActor @Test func resultPanelDoesNotTouchClipboard() {
    let before = NSPasteboard.general.changeCount
    let panel = TranslationResultPanel.show(original: "hello")
    #expect(!panel.isShowingResult)
    panel.show(translation: "안녕하세요", source: "en", target: "ko")
    #expect(panel.isShowingResult)
    #expect(NSPasteboard.general.changeCount == before)
    panel.dismiss()
}

@MainActor @Test func languageNamesFallBackToCode() {
    #expect(!TranslationResultPanel.name("ko").isEmpty)
}
