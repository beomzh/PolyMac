import Foundation

/// 화면 문구의 언어. 기본은 macOS 설정을 따른다.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, ko, en
}

/// 한국어·영어 문구 고르기. 문구는 쓰는 자리에 두 언어를 함께 적는다: `L("저장", "Save")`
/// — 번역 키를 따로 관리하지 않아 빠진 번역이 생기지 않고, 보간(\(n)개)도 그대로 쓴다.
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

    /// 실제로 쓰는 언어: "시스템"이면 macOS 첫 번째 선호 언어가 한국어일 때만 한국어, 그 밖에는 영어
    public static var resolved: AppLanguage {
        switch override ?? cached {
        case .ko: return .ko
        case .en: return .en
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .ko : .en
        }
    }

    public static var isEnglish: Bool { resolved == .en }
}

/// 현재 언어의 문구
@inline(__always)
public func L(_ ko: String, _ en: String) -> String { L10n.isEnglish ? en : ko }
