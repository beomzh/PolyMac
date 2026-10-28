import CoreGraphics
import Testing
@testable import OCRModule

/// 위에서부터 한 줄씩 (높이 0.04, 간격 0.01)
private func lines(_ texts: [String], gapAfter: Int? = nil) -> [LineJoiner.Line] {
    var y: CGFloat = 0.9
    return texts.enumerated().map { i, text in
        let line = LineJoiner.Line(text: text, box: CGRect(x: 0.1, y: y, width: 0.8, height: 0.04))
        y -= 0.05
        if i == gapAfter { y -= 0.06 } // 문단 사이 빈 줄
        return line
    }
}

@Test func keepsLinesByDefault() {
    #expect(LineJoiner.join(lines(["첫 줄", "둘째 줄"]), mode: .keep) == "첫 줄\n둘째 줄")
}

@Test func joinsParagraphsAndKeepsParagraphBreaks() {
    let input = lines(["맥에서 만든 한글 파일명이", "윈도우에서 깨지는 문제.", "다음 문단은 여기서", "시작합니다."], gapAfter: 1)
    #expect(LineJoiner.join(input, mode: .paragraphs) == "맥에서 만든 한글 파일명이 윈도우에서 깨지는 문제.\n다음 문단은 여기서 시작합니다.")
}

@Test func singleLineAndEnglishHyphens() {
    #expect(LineJoiner.join(lines(["recog-", "nition works", "well"]), mode: .singleLine) == "recognition works well")
    #expect(LineJoiner.join(lines(["E-", "Mail"]), mode: .singleLine) == "E- Mail") // 대문자 앞 하이픈은 남김
}
