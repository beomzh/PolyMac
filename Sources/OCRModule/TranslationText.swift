import Foundation

/// 번역 전후의 줄 구조. Apple 번역은 줄바꿈 하나를 빈 줄로 늘리고 들여쓰기를 지우며, 글 전체를 한 번에 넘기면 줄 사이가 뒤섞인다.
/// 그래서 줄 단위 조각으로 나눠 조각마다 번역하고, 들여쓰기·목록 기호·빈 줄은 번역에 넘기지 않고 그대로 되붙인다.
public enum TranslationText {
    public struct Block: Equatable, Sendable {
        /// 번역하지 않는 앞부분 (들여쓰기, 목록 기호). 빈 줄·기호만 있는 줄은 줄 전체.
        public var prefix: String
        /// 번역할 글. 없으면 ""
        public var body: String
    }

    public static func blocks(_ text: String) -> [Block] {
        var result: [Block] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let (prefix, body) = split(line)
            let marker = prefix.contains { !$0.isWhitespace }
            guard body.contains(where: \.isLetter) else {
                result.append(Block(prefix: line, body: ""))
                continue
            }
            if !marker, let last = result.last, last.prefix == prefix, continues(last.body, with: body) {
                result[result.count - 1].body = LineJoiner.glue(last.body, body)
                continue
            }
            result.append(Block(prefix: prefix, body: body))
        }
        return result
    }

    /// translated: 조각 번호 → 번역문. 빠진 조각은 원문 그대로 둔다.
    public static func rebuild(_ blocks: [Block], translated: [Int: String]) -> String {
        blocks.enumerated().map { index, block in
            guard !block.body.isEmpty else { return block.prefix }
            let text = (translated[index] ?? block.body).split(whereSeparator: \.isNewline).joined(separator: " ")
            return block.prefix + text.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    /// 들여쓰기·목록 기호와 나머지 ("  - 글" → "  - ", "글")
    static func split(_ line: String) -> (prefix: String, body: String) {
        let range = line.range(of: #"^\s*(?:[-*•·–]\s+|\d{1,3}[.)]\s+)?"#, options: .regularExpression)
        let end = range?.upperBound ?? line.startIndex
        return (String(line[..<end]), String(line[end...]).trimmingCharacters(in: .whitespaces))
    }

    /// 화면 폭 때문에 끊긴 문장인지: 앞 조각이 문장 끝이 아니고 다음 줄이 소문자로 시작
    private static func continues(_ previous: String, with next: String) -> Bool {
        guard let end = previous.last, let start = next.first, !previous.isEmpty else { return false }
        return !".!?:;。！？".contains(end) && start.isLowercase
    }
}
