import Foundation
import Testing
@testable import ClipboardModule

@Suite struct SearchHighlightTests {
    @Test func wordsSplitAndNormalize() {
        #expect(SearchHighlight.words("  Hello  세계 ") == ["hello", "세계"])
        #expect(SearchHighlight.words("") == [])
    }

    @Test func rangesIgnoreCaseAndMerge() {
        let text = "Error: error ERROR"
        let found = SearchHighlight.ranges(of: ["error"], in: text).map { String(text[$0]) }
        #expect(found == ["Error", "error", "ERROR"])
        // 겹치는 단어는 한 덩어리로
        let merged = SearchHighlight.ranges(of: ["abc", "bcd"], in: "xabcdx").map { String("xabcdx"[$0]) }
        #expect(merged == ["abcd"])
    }

    @Test func decomposedHangulMatches() {
        let nfd = "보고서_최종.pdf".decomposedStringWithCanonicalMapping
        let found = SearchHighlight.ranges(of: SearchHighlight.words("최종"), in: nfd)
        #expect(found.count == 1)
        #expect(String(nfd[found[0]]).precomposedStringWithCanonicalMapping == "최종")
    }

    @Test func oneLineStartsNearMatch() {
        let text = String(repeating: "a", count: 500) + "\nneedle here"
        let line = SearchHighlight.oneLine(text, words: ["needle"])
        #expect(line.hasPrefix("…"))
        #expect(line.contains("⏎ needle here"))
        // 앞쪽 일치, 검색어 없음은 처음부터
        #expect(SearchHighlight.oneLine("  needle\nx", words: ["needle"]) == "needle ⏎ x")
        #expect(SearchHighlight.oneLine("a\nb", words: []) == "a ⏎ b")
    }
}
