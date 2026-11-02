import Foundation
import PolyMacCore

/// 인식한 글에서 웹 주소 찾기. 찾기만 하고 열지 않는다 — 사용자가 알림의 단추를 눌러야 연다
/// (QR 코드·화면 속 글은 누구나 만들 수 있어 저절로 열면 피싱에 쓰일 수 있다).
public enum LinkDetector {
    /// http·https 주소만, 나온 순서대로, 같은 주소는 한 번. "github.com/…"처럼 앞이 빠진 주소는 https로.
    public static func links(in text: String, limit: Int = 3) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        var out: [URL] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard var url = match.url, let scheme = url.scheme?.lowercased() else { continue }
            if scheme == "http", let range = Range(match.range, in: text), !text[range].lowercased().hasPrefix("http") {
                // 앞이 빠진 주소는 NSDataDetector가 http로 채운다 — 요즘 사이트는 거의 https
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.scheme = "https"
                url = components?.url ?? url
            }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                  seen.insert(url.absoluteString).inserted
            else { continue }
            out.append(url)
            if out.count == limit { break }
        }
        return out
    }

    /// 단추 제목: 실제로 열릴 곳(호스트)이 보이게
    public static func title(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.count > 1 ? url.path : ""
        let shown = host + (path.count > 24 ? String(path.prefix(24)) + "…" : path)
        return L("열기: ", "Open: ") + shown
    }
}
