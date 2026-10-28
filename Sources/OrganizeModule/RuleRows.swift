import Foundation
import PolyMacCore

/// 편집 화면에서 다루기 쉬운 조건 한 줄. Condition(중첩 enum)과 서로 바꾼다.
public struct ConditionRow: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case allFiles, fileExtension, kind, name, sourceDomain, sizeGreaterThan, sizeLessThan, addedMoreThan, notOpenedFor, isDuplicate
    }

    public var id = UUID()
    public var kind: Kind = .fileExtension
    /// "아님"
    public var negated = false
    /// 확장자·도메인(쉼표로 구분), 이름 패턴
    public var text = ""
    public var isRegex = false
    /// MB 또는 일
    public var number: Double = 0
    public var kinds: Set<FileKind> = []

    public init(kind: Kind = .fileExtension) {
        self.kind = kind
    }

    public init(_ condition: Condition) {
        self.init()
        switch condition {
        case .not(let inner):
            self = ConditionRow(inner)
            negated.toggle()
        case .fileExtension(let extensions):
            kind = .fileExtension; text = extensions.joined(separator: ", ")
        case .kind(let kinds):
            kind = .kind; self.kinds = Set(kinds)
        case .nameMatches(let pattern, let isRegex):
            kind = .name; text = pattern; self.isRegex = isRegex
        case .sourceDomain(let domains):
            kind = .sourceDomain; text = domains.joined(separator: ", ")
        case .sizeGreaterThan(let bytes):
            kind = .sizeGreaterThan; number = Double(bytes) / Self.mb
        case .sizeLessThan(let bytes):
            kind = .sizeLessThan; number = Double(bytes) / Self.mb
        case .addedMoreThan(let days):
            kind = .addedMoreThan; number = days
        case .notOpenedFor(let days):
            kind = .notOpenedFor; number = days
        case .isDuplicate:
            kind = .isDuplicate
        case .allFiles:
            kind = .allFiles
        }
    }

    static let mb: Double = 1_000_000

    /// 값이 비어 있으면 nil (저장하지 않음)
    public var condition: Condition? {
        let list = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let base: Condition?
        switch kind {
        case .fileExtension:
            base = list.isEmpty ? nil : .fileExtension(extensions: list.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }.map { $0.lowercased() })
        case .kind:
            base = kinds.isEmpty ? nil : .kind(kinds: FileKind.allCases.filter(kinds.contains))
        case .name:
            let pattern = text.trimmingCharacters(in: .whitespaces)
            base = pattern.isEmpty ? nil : .nameMatches(pattern: pattern, isRegex: isRegex)
        case .sourceDomain:
            base = list.isEmpty ? nil : .sourceDomain(domains: list)
        case .sizeGreaterThan:
            base = .sizeGreaterThan(bytes: Int64(max(number, 0) * Self.mb))
        case .sizeLessThan:
            base = .sizeLessThan(bytes: Int64(max(number, 0) * Self.mb))
        case .addedMoreThan:
            base = .addedMoreThan(days: max(number, 0))
        case .notOpenedFor:
            base = .notOpenedFor(days: max(number, 0))
        case .isDuplicate:
            base = .isDuplicate
        case .allFiles:
            base = .allFiles
        }
        guard let base else { return nil }
        return negated ? .not(condition: base) : base
    }

    public static func title(_ kind: Kind) -> String {
        switch kind {
        case .fileExtension: return L("확장자", "Extension")
        case .kind: return L("종류", "Kind")
        case .name: return L("이름", "Name")
        case .sourceDomain: return L("받은 사이트", "Downloaded from")
        case .sizeGreaterThan: return L("크기 > (MB)", "Size > (MB)")
        case .sizeLessThan: return L("크기 < (MB)", "Size < (MB)")
        case .addedMoreThan: return L("받은 지 (일) 지남", "Added more than (days) ago")
        case .notOpenedFor: return L("안 연 지 (일) 지남", "Not opened for (days)")
        case .isDuplicate: return L("같은 내용의 파일이 이미 있음", "Same file already exists")
        case .allFiles: return L("모든 파일", "All files")
        }
    }
}

/// 편집 화면의 동작 한 줄
public struct ActionRow: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case move, copy, rename, trash, addTag, notify
    }

    public var id = UUID()
    public var kind: Kind = .move
    /// 폴더·이름 템플릿·태그
    public var text = ""

    public init(kind: Kind = .move, text: String = "") {
        self.kind = kind
        self.text = text
    }

    public init(_ action: Action) {
        self.init()
        switch action {
        case .move(let to): kind = .move; text = to
        case .copy(let to): kind = .copy; text = to
        case .rename(let template): kind = .rename; text = template
        case .trash: kind = .trash
        case .addTag(let name): kind = .addTag; text = name
        case .notify: kind = .notify
        }
    }

    public var needsText: Bool { [.move, .copy, .rename, .addTag].contains(kind) }

    public var action: Action? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if needsText && value.isEmpty { return nil }
        switch kind {
        case .move: return .move(to: value)
        case .copy: return .copy(to: value)
        case .rename: return .rename(template: value)
        case .trash: return .trash
        case .addTag: return .addTag(name: value)
        case .notify: return .notify
        }
    }

    public static func title(_ kind: Kind) -> String {
        switch kind {
        case .move: return L("폴더로 이동", "Move to folder")
        case .copy: return L("폴더로 복사", "Copy to folder")
        case .rename: return L("이름 바꾸기", "Rename")
        case .trash: return L("휴지통으로", "Move to Trash")
        case .addTag: return L("태그 붙이기", "Add tag")
        case .notify: return L("알림만", "Notify only")
        }
    }
}

public extension FileKind {
    var title: String {
        switch self {
        case .image: return L("이미지", "Image")
        case .video: return L("동영상", "Video")
        case .audio: return L("오디오", "Audio")
        case .document: return L("문서", "Document")
        case .archive: return L("압축 파일", "Archive")
        case .installer: return L("설치 파일", "Installer")
        case .code: return L("코드", "Code")
        case .other: return L("기타", "Other")
        }
    }
}

/// 중복 판정: 브라우저·Finder가 붙이는 번호("이름 (1).pdf", "이름 2.pdf")를 뗀 원래 이름.
/// 번호가 없으면 nil. 실제 중복인지는 내용까지 같은지 따로 확인한다.
public enum DuplicateName {
    public static func original(of name: String) -> String? {
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        guard let range = base.range(of: #"( \(\d{1,3}\)| \d{1,3})$"#, options: .regularExpression) else { return nil }
        let stripped = String(base[..<range.lowerBound])
        guard !stripped.isEmpty else { return nil }
        return ext.isEmpty ? stripped : stripped + "." + ext
    }
}
