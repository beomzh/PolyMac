import Foundation
import PolyMacCore

/// 폴더·이름 칸에 쓰는 치환어 ({name} 등) 목록, 입력 중 자동완성, 예시 미리보기. RuleEngine.render와 같은 목록이다.
public enum TemplateTokens {
    public struct Token: Equatable, Sendable {
        public let text: String
        public let help: String
    }

    public static var all: [Token] {
        [
            Token(text: "{name}", help: L("확장자 뺀 원래 이름", "original name without extension")),
            Token(text: "{ext}", help: L("확장자", "extension")),
            Token(text: "{kind}", help: L("종류 (image, document…)", "kind (image, document…)")),
            Token(text: "{domain}", help: L("받은 사이트", "download site")),
            Token(text: "{yyyy}", help: L("연도", "year")),
            Token(text: "{MM}", help: L("월", "month")),
            Token(text: "{dd}", help: L("일", "day")),
        ]
    }

    /// 끝에 닫히지 않은 `{…`가 있으면 그 글자 (예: "사진_{ya" → "ya"). 없으면 nil.
    public static func openPartial(in text: String) -> String? {
        guard let open = text.lastIndex(of: "{") else { return nil }
        let rest = text[text.index(after: open)...]
        guard !rest.contains("}"), rest.allSatisfy({ $0.isLetter }) else { return nil }
        return String(rest)
    }

    /// 입력 중이면 앞글자가 맞는 것만 (대소문자 무시), 아니면 전부
    public static func suggestions(for text: String) -> [Token] {
        guard let partial = openPartial(in: text), !partial.isEmpty else { return all }
        return all.filter { $0.text.dropFirst().lowercased().hasPrefix(partial.lowercased()) }
    }

    /// 입력 중인 `{…`를 고른 치환어로 바꾸고, 아니면 끝에 붙인다
    public static func insert(_ token: Token, into text: String) -> String {
        if openPartial(in: text) != nil, let open = text.lastIndex(of: "{") {
            return String(text[..<open]) + token.text
        }
        return text + token.text
    }

    /// 목록에 없는 `{…}` (오타 — 그대로 이름에 들어간다)
    public static func unknown(in text: String) -> [String] {
        let known = Set(all.map(\.text))
        var found: [String] = []
        var rest = text[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let token = String(rest[open...close])
            if !known.contains(token), !found.contains(token) { found.append(token) }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    /// 예시 파일로 바꿔 본 결과
    public static func preview(_ template: String, rename: Bool, now: Date = Date()) -> String {
        let sample = FileFacts(name: L("보고서.pdf", "report.pdf"), size: 1_000, addedAt: now, sourceURLs: ["https://example.com/files/report.pdf"])
        // 실제 동작과 같은 규칙으로 (이름에 {ext}가 없으면 원래 확장자를 붙인다)
        if rename, case .rename(let name) = RuleEngine.render(.rename(template: template), sample, now: now) { return name }
        return (RuleEngine.render(template, sample, now: now) as NSString).abbreviatingWithTildeInPath
    }
}
