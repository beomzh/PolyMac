import Foundation

/// 파일 종류. 확장자 → UTType 판정으로 결정한다.
public enum FileKind: String, Codable, Sendable, CaseIterable {
    case image, video, audio, document, archive, installer, code, other
}

/// 규칙의 조건. 모두 Codable이라 규칙을 JSON으로 저장·공유할 수 있다.
/// 연관값에 이름을 붙여 둬야 JSON이 `{"kind":{"kinds":["image"]}}`처럼 사람이 읽고 고칠 수 있는 형태가 된다.
public indirect enum Condition: Codable, Sendable, Equatable {
    /// 대소문자 무시, 점 없이 ("pdf")
    case fileExtension(extensions: [String])
    case kind(kinds: [FileKind])
    /// isRegex == false면 와일드카드(`*견적서*`)
    case nameMatches(pattern: String, isRegex: Bool)
    /// 하위 도메인 포함. "*.go.kr"처럼 앞에 `*.`를 붙여도 같은 의미
    case sourceDomain(domains: [String])
    case sizeGreaterThan(bytes: Int64)
    case sizeLessThan(bytes: Int64)
    case addedMoreThan(days: Double)
    case notOpenedFor(days: Double)
    case isDuplicate
    case not(condition: Condition)
}

public enum MatchMode: String, Codable, Sendable {
    case all  // AND
    case any  // OR
}

/// 규칙의 동작. 경로·이름에는 템플릿 토큰을 쓸 수 있다 (RuleEngine.render 참고).
public enum Action: Codable, Sendable, Equatable {
    case move(to: String)
    case copy(to: String)
    case rename(template: String)
    case trash
    case addTag(name: String)
    /// 손대지 않고 "정리 후보"로만 알림
    case notify
}

public struct OrganizeRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var match: MatchMode
    public var conditions: [Condition]
    public var actions: [Action]
    /// true면 이 규칙이 적용된 파일은 다음 규칙을 검사하지 않는다.
    public var stopAfterMatch: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        match: MatchMode = .all,
        conditions: [Condition],
        actions: [Action],
        stopAfterMatch: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.conditions = conditions
        self.actions = actions
        self.stopAfterMatch = stopAfterMatch
    }
}

public struct WatchedFolder: Codable, Sendable, Equatable {
    /// `~` 허용
    public var path: String
    public var isEnabled: Bool

    public init(path: String, isEnabled: Bool = true) {
        self.path = path
        self.isEnabled = isEnabled
    }
}

/// 모듈 설정 전체. 모듈 on/off → 폴더별 on/off → 규칙별 on/off 3단계.
public struct OrganizeSettings: Codable, Sendable, Equatable {
    /// 저장 형식 버전. 형식이 바뀌면 올리고 이전 버전 변환 코드를 남긴다 (docs/RELEASING.md 1).
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int = OrganizeSettings.currentSchemaVersion
    public var isEnabled: Bool = false
    /// 처음 켜면 미리보기 모드 — 실제로 옮기지 않고 계획만 보여준다.
    public var dryRun: Bool = true
    public var watchedFolders: [WatchedFolder] = [WatchedFolder(path: "~/Downloads")]
    public var rules: [OrganizeRule] = OrganizePresets.all
    /// 다운로드 완료 후 이만큼 지난 파일만 처리 (초)
    public var settleDelay: TimeInterval = 10
    /// 다운로드 중이거나 임시 파일
    public var ignoredExtensions: [String] = ["crdownload", "download", "part", "partial", "tmp"]

    public init() {}
}
