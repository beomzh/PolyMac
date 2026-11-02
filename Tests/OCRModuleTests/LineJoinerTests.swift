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

/// 고정폭 글꼴처럼: 한 칸 폭 0.01, 줄 앞 공백 수만큼 오른쪽에서 시작
private func monoLines(_ texts: [String]) -> [LineJoiner.Line] {
    texts.enumerated().map { i, text in
        let indent = text.prefix { $0 == " " }.count
        let body = String(text.dropFirst(indent))
        return LineJoiner.Line(text: body, box: CGRect(x: 0.05 + CGFloat(indent) * 0.01, y: 0.9 - CGFloat(i) * 0.05,
                                                     width: CGFloat(body.count) * 0.01, height: 0.04))
    }
}

@Test func keepsCodeIndentation() {
    let code = ["func run() {", "    let x = 1", "    if x > 0 {", "        print(x)", "    }", "}"]
    #expect(LineJoiner.join(monoLines(code), mode: .keep, indent: true) == code.joined(separator: "\n"))
    #expect(LineJoiner.join(monoLines(code), mode: .keep, indent: false) == code.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
}

@Test func ignoresSmallJitterAndSideBySideLines() {
    // 한 칸 차이는 흔들림
    #expect(LineJoiner.join(monoLines(["first line here", " next line"]), mode: .keep, indent: true) == "first line here\nnext line")
    // 같은 높이에 나란히 있는 줄(두 단·표)은 위치를 들여쓰기로 보지 않는다
    let side = [LineJoiner.Line(text: "왼쪽 단 글", box: CGRect(x: 0.05, y: 0.9, width: 0.1, height: 0.04)),
                LineJoiner.Line(text: "오른쪽 단 글", box: CGRect(x: 0.55, y: 0.9, width: 0.12, height: 0.04))]
    #expect(LineJoiner.join(side, mode: .keep, indent: true) == "왼쪽 단 글\n오른쪽 단 글")
    // 다른 줄바꿈 방식에는 영향이 없다
    #expect(LineJoiner.join(monoLines(["a = 1", "    b = 2"]), mode: .singleLine, indent: true) == "a = 1 b = 2")
}

@Test func countsKoreanAsTwoCells() {
    #expect(LineJoiner.isWide("한".unicodeScalars.first!))
    #expect(!LineJoiner.isWide("a".unicodeScalars.first!))
}
