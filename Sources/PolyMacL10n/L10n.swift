import Foundation

/// 화면 문구의 언어. 기본은 macOS 설정을 따른다.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, ko, en, ja
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
}

/// 화면 문구 고르기. 문구는 쓰는 자리에 한국어·영어를 함께 적는다: `L("저장", "Save")`
/// — 보간(\(n)개)도 그대로 쓴다. 일본어·중국어는 영어 문구를 키로 번역표(Catalog+<언어>.swift)에서 찾고,
/// 보간 자리는 차례대로 {0}, {1}…로 바꿔 찾는다. 번역이 빠지면 scripts/check-l10n.py가 실패한다.
public enum L10n {
    public static let defaultsKey = "app.language"

    /// 테스트에서 언어를 고정할 때만 쓴다 (설정에 저장하지 않음)
    nonisolated(unsafe) public static var override: AppLanguage?

    nonisolated(unsafe) private static var cached: AppLanguage = {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }()

    /// 사용자가 고른 언어 (설정에 저장)
    public static var language: AppLanguage {
        get { cached }
        set {
            cached = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// 실제로 쓰는 언어: "시스템"이면 macOS 첫 번째 선호 언어 (지원하지 않는 언어면 영어)
    public static var resolved: AppLanguage {
        let chosen = override ?? cached
        return chosen == .system ? matching(Locale.preferredLanguages) : chosen
    }

    /// macOS 선호 언어 목록의 첫 번째에 맞는 화면 언어. 중국어는 글자(간체·번체)까지 본다 — zh-TW, zh-HK는 번체.
    public static func matching(_ preferred: [String]) -> AppLanguage {
        guard let first = preferred.first else { return .en }
        let language = Locale.Language(identifier: first)
        switch language.languageCode?.identifier {
        case "ko": return .ko
        case "ja": return .ja
        case "zh": return language.maximalIdentifier.contains("Hant") ? .zhHant : .zhHans
        default: return .en
        }
    }

    public static var isEnglish: Bool { resolved == .en }

    /// 영어 문구를 현재 언어(일본어·중국어)로. 번역표에 없으면 영어 그대로.
    static func translate(_ en: LString, to language: AppLanguage) -> String {
        let table: [String: String]
        switch language {
        case .ja: table = Catalog.ja
        case .zhHans: table = Catalog.zhHans
        case .zhHant: table = Catalog.zhHant
        case .system, .ko, .en: return en.text
        }
        guard var text = table[en.key] else { return en.text }
        for (n, value) in en.arguments.enumerated() {
            text = text.replacingOccurrences(of: "{\(n)}", with: value)
        }
        return text
    }

    /// 한국어·영어 한 쌍을 현재 언어로 — 문구를 값으로 들고 다니는 곳(모듈 이름 등)에서 쓴다
    public static func text(ko: String, en: String) -> String {
        L(ko, LString(stringLiteral: en))
    }
}

/// 영어 문구. 보간한 값은 따로 들고 있어 번역표의 {0}, {1}… 자리에 넣는다.
public struct LString: ExpressibleByStringInterpolation, Sendable {
    /// 번역표 키: 보간 자리를 {0}, {1}…로 바꾼 영어 문구
    public let key: String
    /// 그대로 쓸 영어 문구
    public let text: String
    public let arguments: [String]

    public init(stringLiteral value: String) {
        key = value
        text = value
        arguments = []
    }

    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        text = stringInterpolation.text
        arguments = stringInterpolation.arguments
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = "", text = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 3)
            text.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            key += literal
            text += literal
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            let s = String(describing: value)
            key += "{\(arguments.count)}"
            text += s
            arguments.append(s)
        }
    }
}

/// 현재 언어의 문구
public func L(_ ko: String, _ en: LString) -> String {
    switch L10n.resolved {
    case .ko: return ko
    case .system, .en: return en.text
    case let language: return L10n.translate(en, to: language)
    }
}
