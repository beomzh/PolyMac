import Foundation

/// macOS가 만든 NFD(자소분리) 파일명을 NFC(완성형)로 바꾼다.
public enum HangulNormalizer {
    /// NFD 등 NFC가 아닌 형태인지 검사한다.
    /// Swift `String ==`는 정규화 형태가 달라도 같다고 보므로 반드시 스칼라 단위로 비교한다.
    public static func needsNFC(_ s: String) -> Bool {
        !s.unicodeScalars.elementsEqual(s.precomposedStringWithCanonicalMapping.unicodeScalars)
    }

    public static func nfc(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
    }

    public struct RenameError: Error {
        public let path: String
        public let errno: Int32
    }

    /// 파일 이름을 NFC로 바꾼다. 바꿀 필요가 없으면 nil.
    /// - `name`은 반드시 `FileManager.contentsOfDirectory(atPath:)` 등 디스크 원본 이름이어야 한다.
    ///   `URL.lastPathComponent`는 이름을 NFD로 분해해서 돌려주므로 실제 형태를 알 수 없다
    ///   (그대로 쓰면 이미 NFC인 파일도 매번 다시 바꾸고, FSEvents와 맞물려 무한 반복된다).
    /// - FileManager/URL은 경로를 다시 NFD로 분해하므로 POSIX rename(2)에 UTF-8 바이트를 그대로 넘긴다.
    /// - APFS는 정규화를 구분하지 않아 바로 바꾸면 "같은 파일"로 처리될 수 있어 임시 이름을 거친다.
    @discardableResult
    public static func renameToNFC(name: String, inDirectory dir: String) throws -> String? {
        guard needsNFC(name) else { return nil }

        let source = dir + "/" + name
        let target = dir + "/" + nfc(name)
        let temp = dir + "/.polymac-nfc-\(UUID().uuidString)"

        try posixRename(source, temp)
        do {
            try posixRename(temp, target)
        } catch {
            try? posixRename(temp, source) // 원래 이름으로 복구
            throw error
        }
        return target
    }

    /// 폴더 바로 아래 항목 중 NFD 이름을 모두 NFC로 바꾸고, 바뀐 경로를 돌려준다.
    public static func normalizeDirectory(_ dir: String, fileManager: FileManager = .default) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: dir).compactMap { name in
            try renameToNFC(name: name, inDirectory: dir)
        }
    }

    private static func posixRename(_ from: String, _ to: String) throws {
        guard rename(from, to) == 0 else { throw RenameError(path: from, errno: errno) }
    }
}
