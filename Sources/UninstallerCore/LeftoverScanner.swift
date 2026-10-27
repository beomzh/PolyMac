import Foundation

/// 앱이 남기는 파일을 찾는 규칙. 파일 시스템 위치는 주입받아 테스트에서 가짜 폴더로 돌릴 수 있다.
public enum LeftoverScanner {
    public struct Location: Sendable {
        public let directory: URL
        public let kind: LeftoverItem.Kind
        public let requiresAdmin: Bool

        public init(_ directory: URL, _ kind: LeftoverItem.Kind, admin: Bool = false) {
            self.directory = directory
            self.kind = kind
            self.requiresAdmin = admin
        }
    }

    /// 실제 Mac의 탐색 위치
    public static func standardLocations(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Location] {
        let lib = home.appendingPathComponent("Library")
        let sys = URL(fileURLWithPath: "/Library")
        return [
            Location(lib.appendingPathComponent("Application Support"), .appSupport),
            Location(lib.appendingPathComponent("Caches"), .caches),
            Location(lib.appendingPathComponent("Preferences"), .preferences),
            Location(lib.appendingPathComponent("Preferences/ByHost"), .preferences),
            Location(lib.appendingPathComponent("Containers"), .containers),
            Location(lib.appendingPathComponent("Group Containers"), .groupContainers),
            Location(lib.appendingPathComponent("Saved Application State"), .savedState),
            Location(lib.appendingPathComponent("HTTPStorages"), .webData),
            Location(lib.appendingPathComponent("WebKit"), .webData),
            Location(lib.appendingPathComponent("Cookies"), .webData),
            Location(lib.appendingPathComponent("Logs"), .logs),
            Location(lib.appendingPathComponent("Application Scripts"), .other),
            Location(lib.appendingPathComponent("LaunchAgents"), .launchAgent),
            Location(sys.appendingPathComponent("Application Support"), .appSupport, admin: true),
            Location(sys.appendingPathComponent("Caches"), .caches, admin: true),
            Location(sys.appendingPathComponent("Preferences"), .preferences, admin: true),
            Location(sys.appendingPathComponent("LaunchAgents"), .launchAgent, admin: true),
            Location(sys.appendingPathComponent("LaunchDaemons"), .launchDaemon, admin: true),
            Location(sys.appendingPathComponent("PrivilegedHelperTools"), .privilegedHelper, admin: true),
        ]
    }

    /// 앱 하나의 잔여물. 앱 본체도 첫 항목으로 넣는다.
    public static func scan(app: AppBundleInfo, locations: [Location], receipts: [String] = [],
                            receiptDirectory: URL = URL(fileURLWithPath: "/var/db/receipts"),
                            fileManager: FileManager = .default) -> [LeftoverItem] {
        var found: [LeftoverItem] = [
            LeftoverItem(url: app.url, kind: .app, confidence: .exact, reason: "삭제할 앱", requiresAdmin: !isUserWritable(app.url, fileManager)),
        ]
        var seen = Set([app.url.path])
        for location in locations {
            guard let names = try? fileManager.contentsOfDirectory(atPath: location.directory.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                let url = location.directory.appendingPathComponent(name)
                guard !seen.contains(url.path),
                      let (confidence, reason) = match(name: name, url: url, kind: location.kind, app: app)
                else { continue }
                seen.insert(url.path)
                found.append(LeftoverItem(url: url, kind: location.kind, confidence: confidence, reason: reason, requiresAdmin: location.requiresAdmin))
            }
        }
        // pkg 설치 기록 (/var/db/receipts/<id>.plist, .bom)
        for id in receipts where matchesReceipt(id, app: app) {
            for ext in ["plist", "bom"] {
                let url = receiptDirectory.appendingPathComponent("\(id).\(ext)")
                guard fileManager.fileExists(atPath: url.path), seen.insert(url.path).inserted else { continue }
                found.append(LeftoverItem(url: url, kind: .receipt, confidence: .likely, reason: "설치 기록 ID \(id)", requiresAdmin: true))
            }
        }
        return found
    }

    /// 이름과 위치로 이 앱의 것인지 판정. nil이면 관계없음.
    static func match(name: String, url: URL, kind: LeftoverItem.Kind, app: AppBundleInfo) -> (LeftoverItem.Confidence, String)? {
        let base = strippedName(name)
        let id = app.bundleID
        if base.caseInsensitiveCompare(id) == .orderedSame || base.lowercased().hasPrefix(id.lowercased() + ".") {
            return (.exact, "앱 ID(\(id))와 일치")
        }
        // "팀ID.앱ID" (Application Scripts·Group Containers 등) — 팀 ID를 몰라도 형태로 알아본다
        if let dot = base.firstIndex(of: "."), base[..<dot].count == 10, base[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            let rest = base[base.index(after: dot)...].lowercased()
            if rest == id.lowercased() || rest.hasPrefix(id.lowercased() + ".") {
                return (.exact, "개발사 팀 ID + 앱 ID(\(id))와 일치")
            }
        }
        if let team = app.teamID, base.hasPrefix(team + ".") {
            return (.likely, "같은 개발사(팀 \(team))의 데이터")
        }
        if [.launchAgent, .launchDaemon].contains(kind), launchItem(at: url, runs: app) {
            return (.likely, "이 앱 안의 프로그램을 실행하는 항목")
        }
        if [.appSupport, .caches, .logs, .webData, .other].contains(kind) {
            let n = normalized(base), appName = normalized(app.name)
            if appName.count >= 3, n == appName {
                return (.likely, "앱 이름(\(app.name))과 같은 이름")
            }
            if appName.count >= 5, n.contains(appName) {
                return (.guessed, "앱 이름(\(app.name))이 들어간 이름 — 확인 후 선택")
            }
        }
        return nil
    }

    static func matchesReceipt(_ id: String, app: AppBundleInfo) -> Bool {
        let lower = id.lowercased(), bundle = app.bundleID.lowercased()
        if lower == bundle || lower.hasPrefix(bundle + ".") { return true }
        let appName = normalized(app.name)
        return appName.count >= 5 && normalized(id).contains(appName)
    }

    /// 백그라운드 항목 plist가 앱 안의 실행 파일을 가리키는지
    static func launchItem(at url: URL, runs app: AppBundleInfo) -> Bool {
        guard let dict = NSDictionary(contentsOf: url) else { return false }
        var paths: [String] = []
        if let program = dict["Program"] as? String { paths.append(program) }
        if let args = dict["ProgramArguments"] as? [String] { paths.append(contentsOf: args) }
        let appPath = app.url.path
        return paths.contains { $0.hasPrefix(appPath + "/") }
    }

    /// "com.foo.App.plist" → "com.foo.App"
    static func strippedName(_ name: String) -> String {
        for suffix in [".plist", ".savedState", ".binarycookies", ".lockfile"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    static func normalized(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isUserWritable(_ url: URL, _ fm: FileManager) -> Bool {
        fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    // MARK: - 이미 지운 앱의 흔적

    /// 역도메인 형태(com.회사.앱)의 이름인데 그 ID의 앱이 설치돼 있지 않은 항목들을 앱 ID별로 묶는다.
    /// macOS 기본(com.apple.*)은 제외. isInstalled는 그 ID의 앱이 이 Mac에 있는지 알려 준다.
    public static func orphans(locations: [Location], isInstalled: (String) -> Bool,
                               installedIDs: Set<String> = [], fileManager: FileManager = .default) -> [OrphanGroup] {
        var groups: [String: [LeftoverItem]] = [:]
        let installedVendors = Set(installedIDs.map(vendor))
        // 지금 등록된 백그라운드 항목이 실행하는 파일 (관리자 권한 도우미 등) — 쓰이는 중이니 흔적이 아니다
        let launchDirs = locations.filter { [.launchAgent, .launchDaemon].contains($0.kind) }.map(\.directory)
        let referenced = Set(launchDirs.flatMap { dir in
            ((try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []).compactMap { launchProgram(at: dir.appendingPathComponent($0)) }
        }.filter { fileManager.fileExists(atPath: $0) })
        for location in locations where location.kind != .logs {
            guard let names = try? fileManager.contentsOfDirectory(atPath: location.directory.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                guard let id = bundleIDLike(withoutHostSuffix(strippedName(name))), !id.lowercased().hasPrefix("com.apple."),
                      !belongsToInstalled(id, installedIDs),
                      !parentIDs(of: id).contains(where: isInstalled) // com.foo.App.ShipIt → com.foo.App이 설치돼 있으면 그 앱의 것
                else { continue }
                let url = location.directory.appendingPathComponent(name)
                if referenced.contains(url.path) { continue }
                // 백그라운드 항목은 가리키는 프로그램이 아직 있으면 앱 없이 설치된 서비스(보안 프로그램 등) — 건드리지 않는다
                var programMissing = false
                if [.launchAgent, .launchDaemon].contains(location.kind) {
                    guard let program = launchProgram(at: url) else { continue }
                    if fileManager.fileExists(atPath: program) { continue }
                    programMissing = true
                }
                // 같은 회사의 다른 앱이 설치돼 있으면(업데이터·공용 구성요소일 수 있음) 추정으로 낮춘다
                let sameVendor = installedVendors.contains(vendor(id))
                let item = LeftoverItem(
                    url: url, kind: location.kind,
                    confidence: programMissing ? .likely : (sameVendor ? .guessed : .likely),
                    reason: programMissing ? "실행할 프로그램이 이미 지워진 백그라운드 항목"
                        : sameVendor ? "설치된 앱 없음 — 같은 회사의 다른 앱이 있어 공용 구성요소일 수 있음" : "이 ID의 앱이 설치돼 있지 않음",
                    requiresAdmin: location.requiresAdmin
                )
                groups[id, default: []].append(item)
            }
        }
        return groups.map { OrphanGroup(bundleID: $0.key, items: $0.value) }.sorted { $0.bundleID < $1.bundleID }
    }

    public struct OrphanGroup: Sendable, Identifiable {
        public let bundleID: String
        public let items: [LeftoverItem]
        public var id: String { bundleID }

        public init(bundleID: String, items: [LeftoverItem]) {
            self.bundleID = bundleID
            self.items = items
        }
    }

    /// ByHost 설정처럼 끝에 붙은 컴퓨터 UUID를 뗀다 ("com.foo.App.A63A9676-B16D-...")
    static func withoutHostSuffix(_ s: String) -> String {
        guard let dot = s.lastIndex(of: ".") else { return s }
        let last = s[s.index(after: dot)...]
        return UUID(uuidString: String(last)) != nil || (last.count == 12 && last.allSatisfy(\.isHexDigit)) ? String(s[..<dot]) : s
    }

    /// "com.foo.App.ShipIt" → ["com.foo.App"] (점 3개 이상 남는 상위 ID들)
    static func parentIDs(of id: String) -> [String] {
        let parts = id.split(separator: ".")
        guard parts.count > 3 else { return [id] }
        return (3...parts.count).map { parts.prefix($0).joined(separator: ".") }
    }

    /// 백그라운드 항목 plist의 실행 파일 경로
    static func launchProgram(at url: URL) -> String? {
        guard let dict = NSDictionary(contentsOf: url) else { return nil }
        if let program = dict["Program"] as? String { return program }
        return (dict["ProgramArguments"] as? [String])?.first
    }

    /// "com.foo.App.helper" 같은 이름에서 앱 ID 후보. 점이 2개 이상인 역도메인 형태만.
    static func bundleIDLike(_ s: String) -> String? {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, parts.count <= 6,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }),
              let first = parts.first, ["com", "org", "net", "io", "dev", "app", "co", "de", "jp", "kr", "us", "me"].contains(first.lowercased())
        else { return nil }
        return s
    }

    /// 설치된 앱 ID이거나 그 하위 ID(com.foo.App.helper)인지
    static func belongsToInstalled(_ id: String, _ installed: Set<String>) -> Bool {
        let lower = id.lowercased()
        return installed.contains { lower == $0.lowercased() || lower.hasPrefix($0.lowercased() + ".") }
    }

    /// "com.foo.App" → "com.foo"
    static func vendor(_ id: String) -> String {
        id.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
    }
}
