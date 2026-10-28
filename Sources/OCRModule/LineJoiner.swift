import CoreGraphics
import Foundation

/// OCR 결과의 줄바꿈 정리 방법
public enum OCRLineMode: String, CaseIterable, Sendable {
    /// 화면에 보이던 줄 그대로
    case keep
    /// 같은 문단의 줄은 잇고, 문단 사이만 줄바꿈 (PDF·웹 글을 복사할 때)
    case paragraphs
    /// 모두 한 줄로 (검색창·번역기에 넣을 때)
    case singleLine

    public static let defaultsKey = "ocr.lineMode"

    public static var current: OCRLineMode {
        get { OCRLineMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .keep }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// 인식한 줄들을 줄바꿈 방법에 맞게 하나의 글로. 좌표는 Vision처럼 0~1, 왼쪽 아래 기준.
public enum LineJoiner {
    public struct Line: Sendable {
        public let text: String
        public let box: CGRect
        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    public static func join(_ lines: [Line], mode: OCRLineMode) -> String {
        let texts = lines.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch mode {
        case .keep:
            return lines.map(\.text).joined(separator: "\n")
        case .singleLine:
            return texts.reduce("") { glue($0, $1) }
        case .paragraphs:
            var out = ""
            var previous: Line?
            for line in lines {
                let text = line.text.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                if let previous, startsNewParagraph(after: previous, next: line) {
                    out += "\n" + text
                } else {
                    out = out.isEmpty ? text : glue(out, text)
                }
                previous = line
            }
            return out
        }
    }

    /// 다음 줄이 새 문단인지: 줄 사이가 한 줄 높이의 0.8배보다 넓거나, 들여쓰기·내어쓰기가 크거나,
    /// 앞 줄이 짧게 끝났으면(문단 끝) 새 문단으로 본다.
    static func startsNewParagraph(after a: Line, next b: Line) -> Bool {
        let height = max(a.box.height, b.box.height, 0.0001)
        let gap = a.box.minY - b.box.maxY
        if gap > height * 0.8 || gap < -height * 0.5 { return true }       // 문단 간격, 또는 다른 단(위로 올라감)
        if abs(a.box.minX - b.box.minX) > height * 1.5 { return true }      // 들여쓰기·다른 단
        let shortLine = a.box.width < max(a.box.width, b.box.width) * 0.6   // 앞 줄이 일찍 끝남
        let ends = a.text.trimmingCharacters(in: .whitespaces).last.map { ".!?。:".contains($0) } ?? false
        return shortLine && ends
    }

    /// 두 조각 잇기: 영어 줄 끝 하이픈은 붙이고, 나머지는 띄어 쓴다
    static func glue(_ left: String, _ right: String) -> String {
        guard !left.isEmpty else { return right }
        if left.hasSuffix("-"), let first = right.first, first.isLowercase {
            return String(left.dropLast()) + right
        }
        return left + " " + right
    }
}
