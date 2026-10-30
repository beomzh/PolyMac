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

    /// 풀어진 한글(첫소리·가운뎃소리·끝소리 낱자)만 완성형 음절로 붙인다. 바꿀 게 없으면 nil.
    /// 전체 NFC는 한자 호환 문자(U+F900…)·옴(Ω) 기호 같은 다른 글자까지 바꿔서, 사용자가 쓴 글자에는 이것만 쓴다.
    public static func composeHangul(_ s: String) -> String? {
        // 대부분은 낱자가 없다 — 긴 글을 배열로 펼치기 전에 먼저 훑는다
        guard s.unicodeScalars.contains(where: { isLeading($0.value) || isTrailing($0.value) }) else { return nil }
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var changed = false
        var i = 0
        while i < scalars.count {
            let a = scalars[i].value
            let b = i + 1 < scalars.count ? scalars[i + 1].value : 0
            if isLeading(a), isVowel(b) {
                var code = 0xAC00 + ((a - 0x1100) * 21 + (b - 0x1161)) * 28
                var used = 2
                if i + 2 < scalars.count, isTrailing(scalars[i + 2].value) {
                    code += scalars[i + 2].value - 0x11A7
                    used = 3
                }
                out.append(Unicode.Scalar(code)!)
                changed = true
                i += used
                continue
            }
            // 받침 없는 완성형 + 끝소리 낱자 (일부만 풀린 경우)
            if (0xAC00...0xD7A3).contains(a), (a - 0xAC00) % 28 == 0, isTrailing(b) {
                out.append(Unicode.Scalar(a + b - 0x11A7)!)
                changed = true
                i += 2
                continue
            }
            out.append(scalars[i])
            i += 1
        }
        return changed ? String(out) : nil
    }

    // 현대 한글 낱자만 완성형으로 붙는다 (옛한글 낱자는 그대로 둔다)
    private static func isLeading(_ v: UInt32) -> Bool { (0x1100...0x1112).contains(v) }
    private static func isVowel(_ v: UInt32) -> Bool { (0x1161...0x1175).contains(v) }
    private static func isTrailing(_ v: UInt32) -> Bool { (0x11A8...0x11C2).contains(v) }

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

    /// 다운로드 중이거나 앱이 쓰고 있는 임시 파일 — 이름을 바꾸면 그 앱이 파일을 잃을 수 있다.
    public static let inProgressExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    /// 폴더 바로 아래 항목 중 NFD 이름을 모두 NFC로 바꾸고, 바뀐 경로를 돌려준다.
    /// 숨김 파일과 다운로드 중인 파일은 건드리지 않는다.
    public static func normalizeDirectory(_ dir: String, fileManager: FileManager = .default) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: dir).compactMap { name in
            guard !name.hasPrefix("."),
                  !inProgressExtensions.contains((name as NSString).pathExtension.lowercased())
            else { return nil }
            return try renameToNFC(name: name, inDirectory: dir)
        }
    }

    /// 고른 항목과 그 안쪽 전부를 NFC로 (Finder 우클릭 "한글 파일명 정리").
    /// 앱·번들 같은 패키지 안과 .git 폴더, 숨김 항목은 건드리지 않는다. 바뀐 경로를 돌려준다.
    public static func normalizeTree(_ url: URL, fileManager: FileManager = .default) throws -> [String] {
        let parent = (url.path as NSString).deletingLastPathComponent
        // URL은 이름 형태를 잃으므로 디스크에 있는 실제 이름을 찾는다
        let wanted = nfc((url.path as NSString).lastPathComponent)
        guard let onDisk = try fileManager.contentsOfDirectory(atPath: parent).first(where: { nfc($0) == wanted }) else { return [] }
        var renamed = try normalizeInside(parent + "/" + onDisk, fileManager: fileManager)
        if let target = try renameToNFC(name: onDisk, inDirectory: parent) { renamed.append(target) }
        return renamed
    }

    /// NFC가 아닌 이름이 몇 개인지만 센다 (바꾸기 전 확인용)
    public static func countTree(_ url: URL, fileManager: FileManager = .default) -> Int {
        let parent = (url.path as NSString).deletingLastPathComponent
        let wanted = nfc((url.path as NSString).lastPathComponent)
        let onDisk = (try? fileManager.contentsOfDirectory(atPath: parent))?.first { nfc($0) == wanted }
        var count = onDisk.map(needsNFC) == true ? 1 : 0
        guard isPlainFolder(url.path, fileManager),
              let enumerator = fileManager.enumerator(atPath: url.path) else { return count }
        while let relative = enumerator.nextObject() as? String {
            let name = (relative as NSString).lastPathComponent
            if name.hasPrefix(".") || isPackageName(name) {
                enumerator.skipDescendants()
                if name.hasPrefix(".") { continue }
            }
            if needsNFC(name) { count += 1 }
        }
        return count
    }

    private static func normalizeInside(_ dir: String, fileManager: FileManager) throws -> [String] {
        guard isPlainFolder(dir, fileManager) else { return [] }
        var renamed: [String] = []
        for name in try fileManager.contentsOfDirectory(atPath: dir) where !name.hasPrefix(".") {
            renamed += try normalizeInside(dir + "/" + name, fileManager: fileManager)
            if let target = try renameToNFC(name: name, inDirectory: dir) { renamed.append(target) }
        }
        return renamed
    }

    /// 안으로 들어가도 되는 일반 폴더인지 (링크·패키지·.git 제외)
    private static func isPlainFolder(_ path: String, _ fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeDirectory
        else { return false }
        return !isPackageName((path as NSString).lastPathComponent)
    }

    private static func isPackageName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return name == ".git" || ["app", "bundle", "framework", "plugin", "kext", "xcodeproj", "xcworkspace", "photoslibrary", "pkg"].contains(ext)
    }

    private static func posixRename(_ from: String, _ to: String) throws {
        guard rename(from, to) == 0 else { throw RenameError(path: from, errno: errno) }
    }
}
