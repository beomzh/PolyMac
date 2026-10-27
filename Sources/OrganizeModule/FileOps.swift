import Foundation

/// POSIX 파일 조작. FileManager는 경로의 한글을 NFD로 다시 분해하므로 (docs/CONCEPT.md 4.8)
/// 새 이름·폴더를 만들 때는 UTF-8 바이트를 그대로 넘기는 시스템 콜을 쓴다.
enum FileOps {
    struct Failure: LocalizedError {
        let operation: String
        let path: String
        let code: Int32
        var errorDescription: String? { "\(operation) 실패 (\(String(cString: strerror(code)))): \(path)" }
    }

    static func exists(_ path: String) -> Bool { access(path, F_OK) == 0 }

    /// 덮어쓰지 않도록 `이름 (2).확장자` 형태로 비어 있는 경로를 찾는다.
    static func uniquePath(directory: String, name: String) -> String {
        var candidate = directory + "/" + name
        guard exists(candidate) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            candidate = directory + "/" + base + " (\(n))" + (ext.isEmpty ? "" : "." + ext)
            n += 1
        } while exists(candidate)
        return candidate
    }

    static func makeDirectories(_ path: String) throws {
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            if mkdir(current, 0o755) != 0, errno != EEXIST {
                throw Failure(operation: "폴더 만들기", path: current, code: errno)
            }
        }
    }

    static func move(_ from: String, to: String) throws {
        if rename(from, to) == 0 { return }
        guard errno == EXDEV else { throw Failure(operation: "이동", path: from, code: errno) }
        // 다른 디스크: 복사 후 원본 제거
        try copy(from, to: to)
        try FileManager.default.removeItem(atPath: from)
    }

    static func copy(_ from: String, to: String) throws {
        guard copyfile(from, to, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
            throw Failure(operation: "복사", path: from, code: errno)
        }
    }
}
