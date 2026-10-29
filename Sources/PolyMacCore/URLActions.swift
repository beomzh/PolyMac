import AppKit
import os

/// `polymac://<동작>` — 단축어(Shortcuts) 앱 등 다른 자동화에서 PolyMac 기능을 부른다. 모듈이 켜질 때 동작을 등록한다.
///
/// - 기본은 꺼져 있다. 웹 페이지의 링크로도 불릴 수 있어 사용자가 메뉴에서 허용해야만 동작한다.
/// - 단축어의 "X-Callback URL 열기"로 부르면 끝난 뒤 `x-success`(실패는 `x-error`)로 돌아간다.
///   돌아갈 주소는 `shortcuts://`만 연다 — 다른 앱·웹 주소로 튕기는 데 쓰이지 않게.
@MainActor
public enum URLActions {
    /// 끝나면 성공 여부를 돌려준다
    public typealias Handler = (_ query: [String: String]) async -> Bool

    nonisolated public static let scheme = "polymac"
    static let allowKey = "url.allowActions"
    private static var handlers: [String: Handler] = [:]
    private static let logger = Logger(subsystem: "dev.polymac", category: "url")

    public static var isAllowed: Bool {
        get { UserDefaults.standard.bool(forKey: allowKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowKey) }
    }

    public static func register(_ action: String, _ handler: @escaping Handler) {
        handlers[action] = handler
    }

    public static func unregister(_ action: String) {
        handlers[action] = nil
    }

    public static func handle(_ url: URL) {
        guard let request = Request(url) else { return }
        // 주소 전체는 남기지 않는다 (돌아갈 주소에 단축어 이름 등이 들어 있다)
        logger.notice("url action=\(request.action, privacy: .public) allowed=\(isAllowed) known=\(handlers[request.action] != nil)")
        guard isAllowed else {
            Toast.show(L("다른 앱에서 PolyMac을 부르려 했습니다", "Another app tried to run a PolyMac action"),
                       content: L("허용하려면: 메뉴바 › 텍스트 추출 › 단축어·URL로 부르기 허용", "To allow: menu bar › Text Recognition › Allow Shortcuts & URLs"), duration: 4)
            request.finish(false)
            return
        }
        guard let handler = handlers[request.action] else {
            Toast.show(L("모르는 동작이거나 기능이 꺼져 있습니다: \(request.action)", "Unknown action or the feature is off: \(request.action)"))
            request.finish(false)
            return
        }
        Task { @MainActor in request.finish(await handler(request.query)) }
    }

    struct Request {
        let action: String
        let query: [String: String]
        let success: URL?
        let failure: URL?

        /// `polymac://ocr?…` 또는 `polymac://x-callback-url/ocr?x-success=…`
        init?(_ url: URL) {
            guard url.scheme?.lowercased() == URLActions.scheme,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host?.lowercased()
            else { return nil }
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let action = host == "x-callback-url" ? path : host
            guard !action.isEmpty, !action.contains("/") else { return nil }
            self.action = action
            var query: [String: String] = [:]
            for item in components.queryItems ?? [] where query[item.name] == nil { query[item.name] = item.value ?? "" }
            self.query = query
            success = Self.callback(query["x-success"])
            failure = Self.callback(query["x-error"])
        }

        static func callback(_ value: String?) -> URL? {
            guard let value, let url = URL(string: value), url.scheme?.lowercased() == "shortcuts" else { return nil }
            return url
        }

        @MainActor
        func finish(_ ok: Bool) {
            guard let back = ok ? success : failure else { return }
            NSWorkspace.shared.open(back)
        }
    }
}
