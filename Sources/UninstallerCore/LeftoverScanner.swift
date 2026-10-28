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
            Location(lib.appendingPathComponent("Logs/DiagnosticReports"), .crashReports),
            Location(lib.appendingPathComponent("Application Support/CrashReporter"), .crashReports),
            Location(lib.appendingPathComponent("Application Scripts"), .other),
            Location(lib.appendingPathComponent("LaunchAgents"), .launchAgent),
            Location(URL(fileURLWithPath: "/Users/Shared"), .sharedData),
        ] + darwinUserDirectories() + pluginFolders(lib, admin: false) + [
            Location(sys.appendingPathComponent("Logs"), .logs, admin: true),
            Location(sys.appendingPathComponent("Logs/DiagnosticReports"), .crashReports, admin: true),
            Location(sys.appendingPathComponent("Application Support"), .appSupport, admin: true),
            Location(sys.appendingPathComponent("Caches"), .caches, admin: true),
            Location(sys.appendingPathComponent("Preferences"), .preferences, admin: true),
            Location(sys.appendingPathComponent("LaunchAgents"), .launchAgent, admin: true),
            Location(sys.appendingPathComponent("LaunchDaemons"), .launchDaemon, admin: true),
            Location(sys.appendingPathComponent("PrivilegedHelperTools"), .privilegedHelper, admin: true),
        ] + pluginFolders(sys, admin: true)
    }

    /// macOS가 앱마다 따로 두는 숨은 캐시(C)·임시(T) 폴더 — 이름이 앱 ID다
    static func darwinUserDirectories() -> [Location] {
        func dir(_ name: Int32) -> URL? {
            var buffer = [CChar](repeating: 0, count: 1024)
            guard confstr(name, &buffer, buffer.count) > 0 else { return nil }
            return URL(fileURLWithPath: String(cString: buffer))
        }
        return [
            dir(_CS_DARWIN_USER_CACHE_DIR).map { Location($0, .caches) },
            dir(_CS_DARWIN_USER_TEMP_DIR).map { Location($0, .tempFiles) },
        ].compactMap { $0 }
    }

    /// 다른 앱에 꽂혀 동작하는 구성요소 폴더
    static func pluginFolders(_ library: URL, admin: Bool) -> [Location] {
        ["Internet Plug-Ins", "PreferencePanes", "Services", "QuickLook", "Spotlight", "Screen Savers", "Input Methods",
         "Audio/Plug-Ins/Components", "Audio/Plug-Ins/VST", "Audio/Plug-Ins/VST3", "Audio/Plug-Ins/HAL"]
            .map { Location(library.appendingPathComponent($0), .plugins, admin: admin) }
    }

    /// 앱이 /Applications 바로 아래가 아니라 자기 폴더(/Applications/Riot Games/…) 안에 있고,
    /// 그 폴더에 다른 앱이 없으면 폴더째 지운다 (언인스톨러·리소스 등이 같이 남지 않게)
    static func containingFolder(of app: AppBundleInfo, fileManager: FileManager) -> URL? {
        let parent = app.url.deletingLastPathComponent()
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        guard roots.contains(where: { parent.path.hasPrefix($0 + "/") }), !roots.contains(parent.path) else { return nil }
        // 폴더 안(두 단계까지)에 이 앱 말고 다른 앱이 있으면 사용자가 모아 둔 폴더일 수 있으니 건드리지 않는다
        func otherApps(in dir: URL, depth: Int) -> Bool {
            guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return true }
            for name in names {
                let url = dir.appendingPathComponent(name)
                if name.hasSuffix(".app") {
                    if url.path != app.url.path { return true }
                } else if depth < 2 {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, otherApps(in: url, depth: depth + 1) { return true }
                }
            }
            return false
        }
        return otherApps(in: parent, depth: 0) ? nil : parent
    }

    /// 앱 하나의 잔여물. 앱 본체도 첫 항목으로 넣는다.
    public static func scan(app: AppBundleInfo, locations: [Location], receipts: [String] = [],
                            receiptDirectory: URL = URL(fileURLWithPath: "/var/db/receipts"),
                            fileManager: FileManager = .default) -> [LeftoverItem] {
        var found: [LeftoverItem] = [
            LeftoverItem(url: app.url, kind: .app, confidence: .exact, reason: "삭제할 앱", requiresAdmin: !isUserWritable(app.url, fileManager)),
        ]
        var seen = Set([app.url.path])
        if let folder = containingFolder(of: app, fileManager: fileManager) {
            found.append(LeftoverItem(url: folder, kind: .app, confidence: .likely,
                                      reason: "앱이 들어 있는 폴더 — 안에 다른 앱 없음 (설치 관리자·리소스 포함)",
                                      requiresAdmin: !isUserWritable(folder, fileManager)))
            seen.insert(folder.path)
        }
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
        if kind == .crashReports {
            // "Foo-2026-10-27-120000.ips", "Foo_2026-...crash"
            let process = normalized(app.executableName ?? app.name)
            let head = normalized(String(name.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""))
            return process.count >= 3 && head == process ? (.likely, "이 앱(\(app.executableName ?? app.name))의 충돌 기록") : nil
        }
        if kind == .plugins {
            // 플러그인은 자기 번들 ID를 가진다
            let pluginID = Bundle(url: url)?.bundleIdentifier?.lowercased() ?? ""
            if pluginID == id.lowercased() || pluginID.hasPrefix(id.lowercased() + ".") { return (.exact, "앱 ID(\(id))로 시작하는 플러그인") }
            if !pluginID.isEmpty, vendor(pluginID) == vendor(id) { return (.guessed, "같은 회사(\(vendor(id)))의 플러그인 — 확인 후 선택") }
        }
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
        if [.appSupport, .caches, .logs, .webData, .sharedData, .plugins, .other].contains(kind) {
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
                               installedIDs: Set<String> = [], installedNames: Set<String> = [],
                               fileManager: FileManager = .default) -> [OrphanGroup] {
        var groups: [String: [LeftoverItem]] = [:]
        let installedVendors = Set(installedIDs.map(vendor))
        let installedKeys = installedNameKeys(installedIDs: installedIDs, installedNames: installedNames)
        // 지금 등록된 백그라운드 항목이 실행하는 파일 (관리자 권한 도우미 등) — 쓰이는 중이니 흔적이 아니다
        let launchDirs = locations.filter { [.launchAgent, .launchDaemon].contains($0.kind) }.map(\.directory)
        let referenced = Set(launchDirs.flatMap { dir in
            ((try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []).compactMap { launchProgram(at: dir.appendingPathComponent($0)) }
        }.filter { fileManager.fileExists(atPath: $0) })
        for location in locations where location.kind != .logs {
            guard let names = try? fileManager.contentsOfDirectory(atPath: location.directory.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                guard let id = bundleIDLike(withoutHostSuffix(strippedName(name))),
                      !sharedComponentPrefixes.contains(where: { id.lowercased().hasPrefix($0) }),
                      !belongsToInstalled(id, installedIDs),
                      !parentIDs(of: id).contains(where: isInstalled), // com.foo.App.ShipIt → com.foo.App이 설치돼 있으면 그 앱의 것
                      // ID 속 이름이 설치된 앱 이름과 겹치면 그 앱의 것일 수 있다
                      // (Discord: 앱 com.hnc.Discord, 업데이터 com.discord.discord.ShipIt — ID로는 관계가 안 보인다)
                      !nameKeys(id).contains(where: { relatesToInstalled($0, installedKeys) })
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
        addNamedLeftovers(to: &groups, locations: locations, installedIDs: installedIDs, installedNames: installedNames, fileManager: fileManager)
        let kindOrder = LeftoverItem.Kind.allCases
        return groups.map { key, items in
            // 묶음 안에서는 종류 순, 같은 종류는 번호까지 자연스러운 순서로 ("Items 2" < "Items 10")
            OrphanGroup(bundleID: key, items: items.sorted {
                let a = kindOrder.firstIndex(of: $0.kind)!, b = kindOrder.firstIndex(of: $1.kind)!
                return a != b ? a < b : $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            })
        }.sorted { $0.bundleID.lowercased() < $1.bundleID.lowercased() }
    }

    /// 사람이 읽는 이름의 폴더("Riot Games", "Blizzard Entertainment")를 찾는다.
    /// - 이미 지운 앱 ID에서 뽑은 회사·앱 이름(riotgames, riotclient)과 같으면 그 묶음에 넣는다 (유력)
    /// - /Users/Shared의 폴더 중 설치된 앱과 관련 없는 것은 그 이름으로 묶는다 (추정 — 이름만으로 판단)
    /// - macOS 업데이트가 옮겨 둔 "Relocated Items"는 따로 (추정)
    /// 설치된 앱의 이름·회사와 겹치는 폴더는 항상 뺀다.
    static func addNamedLeftovers(to groups: inout [String: [LeftoverItem]], locations: [Location],
                                  installedIDs: Set<String>, installedNames: Set<String>, fileManager: FileManager) {
        let installedKeys = installedNameKeys(installedIDs: installedIDs, installedNames: installedNames)
        func relatesToInstalled(_ n: String) -> Bool { Self.relatesToInstalled(n, installedKeys) }
        // 이미 찾은 앱 ID 묶음의 이름 열쇠
        var keyToGroup: [(key: String, group: String)] = groups.keys.flatMap { id in nameKeys(id).map { ($0, id) } }
        let nameLocations = locations.filter { [.appSupport, .caches, .logs, .sharedData].contains($0.kind) }

        // 1) /Users/Shared: 새 이름 묶음 또는 업데이트 잔여물
        for location in nameLocations where location.kind == .sharedData {
            for name in (try? fileManager.contentsOfDirectory(atPath: location.directory.path)) ?? [] where !name.hasPrefix(".") {
                let url = location.directory.appendingPathComponent(name)
                if name.hasPrefix("Relocated Items") || name.hasPrefix("Previously Relocated Items") {
                    groups["macOS 업데이트가 옮겨 둔 항목", default: []].append(LeftoverItem(
                        url: url, kind: .relocated, confidence: .guessed,
                        reason: "macOS 업데이트가 옮겨 둔 예전 설정 — 안을 확인하고 선택", requiresAdmin: true))
                    continue
                }
                let n = normalized(name)
                guard n.count >= 4, !sharedSystemFolders.contains(name), bundleIDLike(name) == nil, !relatesToInstalled(n) else { continue }
                if let match = keyToGroup.first(where: { similar(n, $0.key) }) {
                    groups[match.group, default: []].append(LeftoverItem(url: url, kind: .sharedData, confidence: .likely,
                                                                         reason: "지운 앱(\(match.group))의 회사·앱 이름과 같은 폴더", requiresAdmin: false))
                } else {
                    let title = "\(name) (이름으로 찾음)"
                    groups[title, default: []].append(LeftoverItem(url: url, kind: .sharedData, confidence: .guessed,
                                                                   reason: "공유 폴더의 앱 데이터 — 관련된 설치 앱이 없음, 확인 후 선택", requiresAdmin: false))
                    keyToGroup.append((n, title))
                }
            }
        }
        // 2) Application Support·Caches·Logs의 이름형 폴더: 위에서 만든 묶음에 붙이기만 한다 (새 묶음은 만들지 않음 — 오탐 방지)
        for location in nameLocations where location.kind != .sharedData {
            for name in (try? fileManager.contentsOfDirectory(atPath: location.directory.path)) ?? [] where !name.hasPrefix(".") {
                let n = normalized(name)
                guard n.count >= 4, bundleIDLike(strippedName(name)) == nil, !relatesToInstalled(n),
                      let match = keyToGroup.first(where: { similar(n, $0.key) })
                else { continue }
                let fromName = match.group.hasSuffix("(이름으로 찾음)")
                groups[match.group, default: []].append(LeftoverItem(
                    url: location.directory.appendingPathComponent(name), kind: location.kind,
                    confidence: fromName ? .guessed : .likely,
                    reason: fromName ? "공유 폴더의 \(match.group.replacingOccurrences(of: " (이름으로 찾음)", with: ""))와 같은 이름 — 확인 후 선택"
                                     : "지운 앱(\(match.group))의 회사·앱 이름과 같은 폴더",
                    requiresAdmin: location.requiresAdmin))
            }
        }
    }

    /// macOS 구성요소이거나 여러 앱이 함께 쓰는 구성요소 — 그 이름의 앱이 없어도 흔적이 아니다
    public static let sharedComponentPrefixes: [String] = [
        "com.apple.",            // macOS
        "org.cups.",             // macOS 프린터 시스템
        "org.swift.",            // Swift 도구 (Xcode·Command Line Tools)
        "org.sparkle-project.",  // 여러 앱이 쓰는 자동 업데이트
        "org.jcef.",             // 앱 안의 웹 화면 (JetBrains 등)
        "org.chromium.",         // 앱 안의 웹 화면
        "com.github.electron",   // Electron 기반 앱 공용
    ]

    /// 회사 단위 묶음 열쇠: "com.riotgames.RiotGames.RiotClient" → "com.riotgames"
    public static func vendorKey(_ id: String) -> String { vendor(id) }

    /// 지운 뒤에도 디스크에 남아 있는 항목만 — 링크는 따라가지 않는다(lstat)
    public static func stillPresent(_ items: [LeftoverItem]) -> [LeftoverItem] {
        items.filter { (try? FileManager.default.attributesOfItem(atPath: $0.url.path)) != nil }
    }

    /// 앱 단위 묶음 열쇠 — 앱 ID 앞 세 부분. 도우미·위젯도 같은 앱으로 묶인다.
    /// "com.alanyan.BatteryMac.BigSurWidget" → "com.alanyan.batterymac"
    public static func appKey(_ id: String) -> String {
        let parts = id.split(separator: ".")
        return (parts.count >= 3 ? parts.prefix(3).joined(separator: ".") : id).lowercased()
    }

    /// 지운 앱의 보여 줄 이름. 앱이 이미 없어 진짜 이름을 물어볼 수 없으므로
    /// 남은 폴더 중 사람이 지은 이름("MapleStory")이 앱 ID의 앱 부분과 같으면 그 이름, 아니면 앱 부분("TRex")
    public static func appTitle(forID id: String, items: [LeftoverItem]) -> String {
        let parts = id.split(separator: ".").map(String.init)
        let component = parts.count >= 3 ? parts[2] : (parts.last ?? id)
        let key = normalized(component)
        let human = items.map { strippedName($0.url.lastPathComponent) }
            .first { bundleIDLike($0) == nil && normalized($0) == key }
        if let human { return human }
        // 소문자뿐인 ID 조각은 첫 글자만 대문자로: "intellij" → "Intellij"
        func display(_ s: String) -> String { s == s.lowercased() ? s.prefix(1).uppercased() + s.dropFirst() : s }
        // "app"·"cli"처럼 그것만으로는 무슨 앱인지 모르는 조각은 회사 이름을 앞에: "Battle App"
        let generic: Set<String> = ["app", "cli", "ui", "client", "helper", "agent", "browser", "launcher",
                                    "bootstrapper", "installer", "desktop", "mac", "macos", "osx"]
        if parts.count >= 3, generic.contains(component.lowercased()) || component.count <= 3 {
            return display(parts[1]) + " " + display(component)
        }
        return display(component)
    }

    /// 설치된 앱의 이름·ID 각 부분을 정규화한 열쇠 (4자 이상)
    static func installedNameKeys(installedIDs: Set<String>, installedNames: Set<String>) -> [String] {
        installedNames.map(normalized).filter { $0.count >= 4 } + installedIDs.flatMap(nameKeys)
    }

    /// 설치된 앱 쪽은 더 넓게 본다 — 애매하면 흔적에서 빼는 게 안전 ("Zoom Data" ~ zoom, "discord" ~ Discord)
    static func relatesToInstalled(_ n: String, _ installedKeys: [String]) -> Bool {
        installedKeys.contains { k in n == k || (k.count >= 4 && n.hasPrefix(k)) || (n.count >= 4 && k.hasPrefix(n)) }
    }

    /// /Users/Shared에 원래 있는 macOS 폴더
    static let sharedSystemFolders: Set<String> = ["SC Info", "adi", "Library", "Shared Items"]

    /// 흔한 단어는 이름 열쇠로 쓰지 않는다
    static let genericWords: Set<String> = ["app", "apps", "mac", "macos", "osx", "desktop", "helper", "agent", "service",
                                            "launcher", "updater", "shipit", "plugin", "plugins", "client", "studio", "pro"]

    /// "com.riotgames.RiotGames.RiotClient" → ["riotgames", "riotclient"]
    static func nameKeys(_ id: String) -> [String] {
        Array(Set(id.split(separator: ".").dropFirst().map { normalized(String($0)) }
            .filter { $0.count >= 4 && !genericWords.contains($0) }))
    }

    /// "riotclientux" ~ "riotclient", "blizzardentertainment" ~ "blizzard"
    static func similar(_ a: String, _ b: String) -> Bool {
        a == b || (b.count >= 5 && a.hasPrefix(b)) || (a.count >= 5 && b.hasPrefix(a))
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
