import Foundation

/// 클립보드 검색어 강조. 걸러내기(refilter)와 같은 규칙: 띄어쓰기로 나눈 단어, 대소문자 무시,
/// 풀어진 한글(NFD)과 붙은 한글(NFC)은 같은 글자로 본다 (Foundation 비교가 정규 등가를 따른다).
enum SearchHighlight {
    static func words(_ query: String) -> [String] {
        query.precomposedStringWithCanonicalMapping.lowercased().split(separator: " ").map(String.init)
    }

    /// text 안에서 단어들이 나온 자리, 앞에서부터 순서대로 (겹치면 합친다). 아주 긴 글은 limit개까지만.
    static func ranges(of words: [String], in text: String, limit: Int = 500) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for word in words where !word.isEmpty {
            var start = text.startIndex
            while found.count < limit, start < text.endIndex,
                  let r = text.range(of: word, options: .caseInsensitive, range: start..<text.endIndex) {
                found.append(r)
                start = r.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in found {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    /// 목록 한 줄 요약. 첫 일치가 뒤쪽에 있으면 그 조금 앞부터 "…"로 시작해 일치가 보이게 한다.
    /// 줄바꿈은 ⏎로 보이고, 한 줄에 보이는 건 몇십 자라 length자만 쓴다.
    static func oneLine(_ text: String, words: [String], lead: Int = 12, length: Int = 300) -> String {
        var start = text.startIndex
        if let first = ranges(of: words, in: text, limit: 1).first {
            start = text.index(first.lowerBound, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex
        }
        let body = String(text[start...].prefix(length))
        let collapsed = (start == text.startIndex ? body.trimmingCharacters(in: .whitespacesAndNewlines) : body)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return start == text.startIndex ? collapsed : "…" + collapsed
    }
}
