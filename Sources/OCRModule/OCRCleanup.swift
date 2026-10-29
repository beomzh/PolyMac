import Foundation

/// 인식 결과의 흔한 기호 오인식 고치기 (scripts/ocr-bench.sh 샘플에서 확인한 것만).
/// Vision은 한글 사이의 가운뎃점(·)을 글머리표(•)로, 말줄임(…)을 "•·•"처럼 읽는다.
public enum OCRCleanup {
    public static func apply(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { fixLine(String($0)) }.joined(separator: "\n")
    }

    static func fixLine(_ line: String) -> String {
        // 점 모양 기호 세 개 → 말줄임 (마침표 "..."는 코드·글에서 그대로 쓰므로 건드리지 않는다)
        var out = line.replacingOccurrences(of: "[•·∙⋅]{3}", with: "…", options: .regularExpression)
        // 줄 맨 앞의 •는 글머리표, 줄 가운데의 •는 가운뎃점
        let indent = out.prefix { $0 == " " || $0 == "\t" }
        var body = String(out.dropFirst(indent.count))
        let lead = body.hasPrefix("•") ? "•" : ""
        body = lead + String(body.dropFirst(lead.count)).replacingOccurrences(of: "•", with: "·")
        out = indent + body
        return out
    }
}

