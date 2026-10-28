import Foundation
import UniformTypeIdentifiers

/// 규칙 평가에 필요한 파일 정보. 디스크를 읽는 쪽과 판단하는 쪽을 나눠 엔진을 순수 함수로 유지한다.
public struct FileFacts: Sendable {
    public var name: String
    public var size: Int64
    public var addedAt: Date
    public var lastOpenedAt: Date?
    /// 다운로드 출처 URL들 (kMDItemWhereFroms)
    public var sourceURLs: [String]
    public var isDuplicate: Bool

    public init(name: String, size: Int64, addedAt: Date, lastOpenedAt: Date? = nil, sourceURLs: [String] = [], isDuplicate: Bool = false) {
        self.name = name
        self.size = size
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.sourceURLs = sourceURLs
        self.isDuplicate = isDuplicate
    }

    public var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    public var baseName: String { (name as NSString).deletingPathExtension }

    public var kind: FileKind {
        let ext = fileExtension
        if ["dmg", "pkg", "mpkg"].contains(ext) { return .installer }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .code }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || ["doc", "docx", "hwp", "hwpx", "pages"].contains(ext) {
            return .document
        }
        return .other
    }

    /// 첫 번째 출처 URL의 호스트 (www. 제거)
    public var sourceDomain: String? {
        guard let host = sourceURLs.lazy.compactMap({ URL(string: $0)?.host }).first else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// 파일 하나에 대해 어떤 규칙이 어떤 동작을 하게 되는지.
public struct PlannedStep: Sendable, Equatable {
    public let ruleID: UUID
    public let ruleName: String
    /// 템플릿이 이미 채워진 동작
    public let actions: [Action]
}

public enum RuleEngine {
    public static func plan(for file: FileFacts, settings: OrganizeSettings, now: Date = Date()) -> [PlannedStep] {
        guard settings.isEnabled else { return [] }
        if settings.ignoredExtensions.contains(file.fileExtension) { return [] }
        if now.timeIntervalSince(file.addedAt) < settings.settleDelay { return [] }

        var steps: [PlannedStep] = []
        for rule in settings.rules where rule.isEnabled && matches(rule, file, now: now) {
            steps.append(PlannedStep(
                ruleID: rule.id,
                ruleName: rule.name,
                actions: rule.actions.map { render($0, file, now: now) }
            ))
            if rule.stopAfterMatch { break }
        }
        return steps
    }

    public static func matches(_ rule: OrganizeRule, _ file: FileFacts, now: Date) -> Bool {
        guard !rule.conditions.isEmpty else { return false } // 조건 없는 규칙이 모든 파일을 건드리지 않게
        switch rule.match {
        case .all: return rule.conditions.allSatisfy { evaluate($0, file, now: now) }
        case .any: return rule.conditions.contains { evaluate($0, file, now: now) }
        }
    }

    public static func evaluate(_ condition: Condition, _ file: FileFacts, now: Date) -> Bool {
        let day: TimeInterval = 86_400
        switch condition {
        case .fileExtension(let exts):
            return exts.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.contains(file.fileExtension)
        case .kind(let kinds):
            return kinds.contains(file.kind)
        case .nameMatches(let pattern, let isRegex):
            return isRegex ? regexMatches(pattern, file.name) : globMatches(pattern, file.name)
        case .sourceDomain(let domains):
            guard let host = file.sourceDomain?.lowercased() else { return false }
            return domains.contains { raw in
                let d = raw.lowercased().replacingOccurrences(of: "*.", with: "")
                return host == d || host.hasSuffix("." + d)
            }
        case .sizeGreaterThan(let bytes):
            return file.size > bytes
        case .sizeLessThan(let bytes):
            return file.size < bytes
        case .addedMoreThan(let days):
            return now.timeIntervalSince(file.addedAt) > days * day
        case .notOpenedFor(let days):
            return now.timeIntervalSince(file.lastOpenedAt ?? file.addedAt) > days * day
        case .isDuplicate:
            return file.isDuplicate
        case .allFiles:
            return true
        case .not(let inner):
            return !evaluate(inner, file, now: now)
        }
    }

    /// 템플릿 토큰: {name} {ext} {kind} {domain} {yyyy} {MM} {dd}
    /// 파일 이름·출처처럼 외부에서 온 값은 경로를 벗어나지 못하게 정리해서 넣는다 (docs/SECURITY.md 4).
    public static func render(_ template: String, _ file: FileFacts, now: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let tokens: [String: String] = [
            "{name}": pathSafe(file.baseName),
            "{ext}": pathSafe(file.fileExtension),
            "{kind}": file.kind.rawValue,
            "{domain}": pathSafe(file.sourceDomain ?? "unknown"),
            "{yyyy}": String(format: "%04d", c.year ?? 0),
            "{MM}": String(format: "%02d", c.month ?? 0),
            "{dd}": String(format: "%02d", c.day ?? 0),
        ]
        return tokens.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    static func render(_ action: Action, _ file: FileFacts, now: Date) -> Action {
        switch action {
        case .move(let to): return .move(to: render(to, file, now: now))
        case .copy(let to): return .copy(to: render(to, file, now: now))
        case .rename(let t):
            // 확장자는 템플릿에 없으면 유지
            let rendered = render(t, file, now: now)
            let hasExt = t.contains("{ext}") || file.fileExtension.isEmpty
            return .rename(template: hasExt ? rendered : rendered + "." + file.fileExtension)
        case .addTag(let tag): return .addTag(name: render(tag, file, now: now))
        case .trash, .notify: return action
        }
    }

    /// 경로 구분자와 상위 폴더 참조를 없애 한 단계 이름으로만 쓰이게 한다.
    static func pathSafe(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        return cleaned.isEmpty ? "_" : cleaned
    }

    private static func globMatches(_ pattern: String, _ name: String) -> Bool {
        fnmatch(pattern.lowercased(), name.lowercased(), 0) == 0
    }

    private static func regexMatches(_ pattern: String, _ name: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}
