import Foundation
import PolyMacCore

/// 규칙 내보내기·가져오기. 감시 폴더·미리보기 모드 같은 이 Mac의 설정은 빼고 규칙만 옮긴다.
/// 가져오기는 이 형식과 organize.json(설정 전체) 둘 다 받는다.
public enum RuleTransfer {
    static let format = "polymac.organize.rules"
    /// 규칙 파일이 이보다 크면 읽지 않는다 — 규칙 수백 개도 수십 KB
    static let maxBytes = 1_000_000

    struct Export: Codable {
        var format: String
        var schemaVersion: Int
        var rules: [OrganizeRule]
    }

    /// 다른 파일(organize.json)에서 schemaVersion과 rules만 꺼내 읽는다
    private struct Envelope: Decodable {
        var format: String?
        var schemaVersion: Int?
        var rules: [OrganizeRule]?
    }

    public static func encode(_ rules: [OrganizeRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(Export(format: format, schemaVersion: OrganizeSettings.currentSchemaVersion, rules: rules))
    }

    /// 읽은 규칙은 모두 꺼진 상태로, 이미 있는 id와 겹치면 새 id로 — 저장하기 전에는 아무것도 바뀌지 않는다
    public static func decode(_ data: Data, existingIDs: Set<UUID> = []) throws -> [OrganizeRule] {
        guard data.count <= maxBytes else {
            throw ModuleError(L("파일이 너무 큽니다 (1MB 넘음). 규칙 파일이 맞는지 확인하세요.", "The file is too large (over 1 MB). Is it a rules file?"))
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ModuleError(L("규칙 파일을 읽지 못했습니다: \(describe(error))", "Could not read the rules file: \(describe(error))"))
        }
        if let f = envelope.format, f != format {
            throw ModuleError(L("PolyMac 규칙 파일이 아닙니다 (\(f))", "Not a PolyMac rules file (\(f))"))
        }
        guard let rules = envelope.rules, let version = envelope.schemaVersion else {
            throw ModuleError(L("규칙 파일이 아닙니다 (rules·schemaVersion 없음)", "Not a rules file (no rules or schemaVersion)"))
        }
        guard version <= OrganizeSettings.currentSchemaVersion else {
            throw ModuleError(L("더 새 버전의 PolyMac에서 내보낸 규칙입니다. 앱을 업데이트한 뒤 가져오세요.", "These rules come from a newer PolyMac. Update the app first."))
        }
        var taken = existingIDs
        return rules.map { rule in
            var r = rule
            r.isEnabled = false
            if taken.contains(r.id) { r.id = UUID() }
            taken.insert(r.id)
            return r
        }
    }

    /// 디코딩 오류에서 어느 키가 문제인지만 짧게
    private static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        let path: (DecodingError.Context) -> String = { ctx in
            ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .dataCorrupted(let ctx): return ctx.codingPath.isEmpty ? L("JSON 형식이 아님", "not JSON") : path(ctx)
        case .keyNotFound(let key, let ctx): return "\(path(ctx)).\(key.stringValue) " + L("없음", "missing")
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx): return path(ctx)
        @unknown default: return error.localizedDescription
        }
    }
}
