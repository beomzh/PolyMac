import Foundation

/// 실행 중인 프로그램이 쓰고 있는 항목 찾기.
/// - 실행 파일이 그 안에 있는 프로세스 (proc_pidpath)
/// - 그 안의 파일을 열어 둔 프로세스 (lsof — 내 계정 프로세스만 보인다)
public enum InUseChecker {
    /// 항목 경로 → 쓰고 있는 프로그램 이름
    public static func users(of paths: [String], ignoringExecutablesUnder ignored: String?) -> [String: String] {
        guard !paths.isEmpty else { return [:] }
        var result: [String: String] = [:]
        func owner(of file: String) -> String? {
            paths.first { file == $0 || file.hasPrefix($0 + "/") }
        }
        func isIgnored(_ exe: String) -> Bool {
            guard let ignored else { return false }
            return exe.hasPrefix(ignored + "/")
        }

        // 1) 실행 중인 프로그램의 실행 파일 위치
        var executables: [Int32: String] = [:]
        let count = proc_listallpids(nil, 0)
        var pids = [Int32](repeating: 0, count: Int(max(count, 0)) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                let exe = String(cString: buffer)
                executables[pid] = exe
                if !isIgnored(exe), let item = owner(of: exe) { result[item] = (exe as NSString).lastPathComponent }
            }
        }

        // 2) 열려 있는 파일
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-w", "-Fpcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return result }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var pid: Int32 = 0, command = ""
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard let item = owner(of: value), result[item] == nil else { continue }
                if let exe = executables[pid], isIgnored(exe) { continue }
                result[item] = command
            default: break
            }
        }
        return result
    }
}
