import AppKit
import PolyMacCore
import Security
import UninstallerCore
import os

/// 앱 삭제 창의 상태. 창을 열 때 만들어지고 닫으면 버린다 (평소에는 메모리를 쓰지 않음).
@MainActor
final class UninstallerModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case apps = "설치된 앱"
        case orphans = "남은 흔적"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .apps
    @Published var apps: [AppBundleInfo] = []
    @Published var query = ""
    @Published var selectedAppID: String? {
        didSet { if let app = apps.first(where: { $0.id == selectedAppID }) { scan(app) } }
    }
    @Published private(set) var items: [LeftoverItem] = []
    @Published private(set) var orphanGroups: [LeftoverScanner.OrphanGroup] = []
    @Published var checked: Set<String> = []
    @Published private(set) var sizes: [String: Int64] = [:]
    /// 안쪽 파일까지 포함한 마지막 수정 시각
    @Published private(set) var modified: [String: Date] = [:]
    /// 지금 열려 있거나 실행 중인 항목 → 쓰고 있는 프로그램 이름. 이 항목은 지우지 않는다.
    @Published private(set) var inUse: [String: String] = [:]
    @Published private(set) var isCheckingUse = false
    /// 선택한 앱을 마지막으로 연 시각 (Spotlight 기록)
    @Published private(set) var appLastUsed: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var isDeleting = false
    @Published var status: String?
    @Published var askConfirm = false

    private var receipts: [String] = []
    private let logger = Logger(subsystem: "dev.polymac", category: "uninstaller")

    var selectedApp: AppBundleInfo? { apps.first { $0.id == selectedAppID } }

    var filteredApps: [AppBundleInfo] {
        let q = query.precomposedStringWithCanonicalMapping.lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.precomposedStringWithCanonicalMapping.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    /// 지금 화면의 후보 전체
    var currentItems: [LeftoverItem] {
        mode == .apps ? items : orphanGroups.flatMap(\.items)
    }

    var checkedItems: [LeftoverItem] { currentItems.filter { checked.contains($0.id) && inUse[$0.id] == nil } }
    var checkedSize: Int64 { checkedItems.reduce(0) { $0 + (sizes[$1.id] ?? 0) } }

    var isSelectedAppRunning: Bool {
        guard let id = selectedApp?.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    // MARK: - 불러오기

    func loadApps() {
        Task.detached(priority: .userInitiated) {
            let found = Self.installedApps()
            let receipts = Self.pkgReceipts()
            await MainActor.run {
                self.apps = found
                self.receipts = receipts
            }
        }
    }

    /// 앱 하나를 직접 고르기 (창에 끌어다 놓은 경우)
    func select(appAt url: URL) {
        guard url.pathExtension == "app", let info = Self.info(url) else {
            status = "앱(.app)만 놓을 수 있습니다"
            return
        }
        if !apps.contains(where: { $0.id == info.id }) { apps.insert(info, at: 0) }
        mode = .apps
        selectedAppID = info.id
    }

    func scan(_ app: AppBundleInfo) {
        items = []
        checked = []
        status = nil
        inUse = [:]
        appLastUsed = Self.lastUsed(app.url)
        guard !app.isSystemApp, app.bundleID != Bundle.main.bundleIdentifier else {
            status = app.isSystemApp ? "macOS 기본 앱은 지울 수 없습니다" : "PolyMac 자신은 여기서 지울 수 없습니다"
            return
        }
        isScanning = true
        let receipts = receipts
        Task.detached(priority: .userInitiated) {
            let found = LeftoverScanner.scan(app: app, locations: LeftoverScanner.standardLocations(), receipts: receipts)
            await MainActor.run {
                guard self.selectedAppID == app.id else { return }
                self.items = found
                self.checked = Set(found.filter { $0.confidence.selectedByDefault }.map(\.id))
                self.isScanning = false
                self.measure(found)
                self.checkInUse(found, ignoringProcessesUnder: app.url)
            }
        }
    }

    func scanOrphans() {
        orphanGroups = []
        checked = []
        status = nil
        isScanning = true
        let installedIDs = Set(apps.map(\.bundleID))
        let installedNames = Set(apps.map(\.name))
        Task.detached(priority: .userInitiated) {
            let groups = LeftoverScanner.orphans(locations: LeftoverScanner.standardLocations(),
                                                 isInstalled: Self.isInstalledAnywhere,
                                                 installedIDs: installedIDs, installedNames: installedNames)
            await MainActor.run {
                self.orphanGroups = groups
                self.checked = Set(groups.flatMap(\.items).filter { $0.confidence.selectedByDefault }.map(\.id))
                self.isScanning = false
                self.status = groups.isEmpty ? "남아 있는 흔적을 찾지 못했습니다" : nil
                self.measure(groups.flatMap(\.items))
                self.checkInUse(groups.flatMap(\.items), ignoringProcessesUnder: nil)
            }
        }
    }

    /// 크기·마지막 수정 시각은 오래 걸릴 수 있어 나중에 채운다
    private func measure(_ list: [LeftoverItem]) {
        let urls = list.map(\.url)
        Task.detached(priority: .utility) {
            for url in urls {
                let (size, newest) = Self.sizeAndNewestModification(url)
                await MainActor.run {
                    self.sizes[url.path] = size
                    if let newest { self.modified[url.path] = newest }
                }
            }
        }
    }

    /// 실행 중인 프로그램이 쓰고 있는 항목을 찾아 지울 대상에서 뺀다.
    /// 지우려는 앱 안의 프로그램은 지우기 전에 앱을 종료하므로 제외한다.
    private func checkInUse(_ list: [LeftoverItem], ignoringProcessesUnder appURL: URL?) {
        let paths = list.map(\.url.path)
        isCheckingUse = true
        Task.detached(priority: .utility) {
            let found = InUseChecker.users(of: paths, ignoringExecutablesUnder: appURL?.path)
            await MainActor.run {
                self.inUse = found
                self.checked.subtract(found.keys)
                self.isCheckingUse = false
            }
        }
    }

    func toggle(_ item: LeftoverItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
    }

    func toggleGroup(_ group: LeftoverScanner.OrphanGroup) {
        let ids = Set(group.items.map(\.id))
        if ids.isSubset(of: checked) { checked.subtract(ids) } else { checked.formUnion(ids) }
    }

    // MARK: - 삭제

    func deleteChecked() {
        let targets = checkedItems
        guard !targets.isEmpty, !isDeleting else { return }
        isDeleting = true
        status = "정리하는 중…"
        let appID = mode == .apps ? selectedApp?.bundleID : nil
        let freed = checkedSize
        Task {
            if let appID, !(await Self.quit(appID)) {
                isDeleting = false
                status = "앱이 아직 실행 중이라 지우지 않았습니다. 앱을 종료한 뒤 다시 시도하세요."
                return
            }
            await Self.unloadLaunchAgents(targets)
            // 폴더와 그 안의 항목을 같이 골랐으면 폴더만 (앱이 든 폴더 등)
            let urls = targets.map(\.url).filter { url in !targets.contains { $0.url != url && url.path.hasPrefix($0.url.path + "/") } }
            var failed = await FinderTrash.move(urls)
            // Finder가 못 옮긴 것(다른 앱의 샌드박스 데이터 등 macOS 보호 항목)은 macOS에 직접 요청 — 허용 창이 뜰 수 있다
            if !failed.isEmpty { failed = await Self.recycle(failed) }
            let moved = targets.count - failed.count
            logger.notice("uninstall moved=\(moved) failed=\(failed.count)")
            AppPaths.appendLine("\(Date())  휴지통으로 \(moved)개 이동, 실패 \(failed.count)개: " + targets.map(\.url.path).joined(separator: " | "),
                                to: AppPaths.dataDirectory.appendingPathComponent("uninstall-log.txt"))
            isDeleting = false
            let size = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
            status = failed.isEmpty
                ? "휴지통으로 \(moved)개(\(size))를 옮겼습니다. Finder 휴지통에서 \"되돌려 놓기\"로 복구할 수 있습니다."
                : "\(moved)개를 옮겼고 \(failed.count)개는 옮기지 못했습니다 — " + failed.prefix(3).map(Self.whyLeft).joined(separator: " · ")
            if mode == .apps, let app = selectedApp {
                if !FileManager.default.fileExists(atPath: app.url.path) {
                    apps.removeAll { $0.id == app.id }
                    items = items.filter { failed.contains($0.url) }
                    checked = []
                } else {
                    scan(app)
                }
            } else {
                orphanGroups = orphanGroups.compactMap { g in
                    let left = g.items.filter { failed.contains($0.url) }
                    return left.isEmpty ? nil : LeftoverScanner.OrphanGroup(bundleID: g.bundleID, items: left)
                }
                checked = []
            }
        }
    }

    // MARK: - 시스템 정보

    nonisolated static func installedApps() -> [AppBundleInfo] {
        let fm = FileManager.default
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        var result: [AppBundleInfo] = []
        func visit(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for name in names where !name.hasPrefix(".") {
                let path = dir + "/" + name
                if name.hasSuffix(".app") {
                    if let info = info(URL(fileURLWithPath: path)), !info.isSystemApp { result.append(info) }
                } else if depth < 2 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { visit(path, depth: depth + 1) }
                }
            }
        }
        roots.forEach { visit($0, depth: 0) }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated static func info(_ url: URL) -> AppBundleInfo? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppBundleInfo(url: url, bundleID: id, name: name,
                             version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                             teamID: teamID(url),
                             executableName: bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
    }

    /// Spotlight가 기록한 마지막 실행 시각
    nonisolated static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// 남은 이유를 사람이 알아보게
    static func whyLeft(_ url: URL) -> String {
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        if url.path.contains("/Library/Containers/") || url.path.contains("/Library/Group Containers/") {
            return "\(path) (macOS가 다른 앱 데이터로 보호 — 허용 창에서 허용하거나 Finder에서 직접 휴지통으로)"
        }
        return path
    }

    /// NSWorkspace로 휴지통 이동 (Finder가 못 옮긴 항목용). 남은 경로를 돌려준다.
    static func recycle(_ urls: [URL]) async -> [URL] {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { _, _ in
                continuation.resume(returning: urls.filter { FileManager.default.fileExists(atPath: $0.path) })
            }
        }
    }

    /// 코드 서명의 개발사 팀 ID
    nonisolated static func teamID(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// 휴지통에 있는 앱은 설치된 것으로 치지 않는다
    nonisolated static func isInstalledAnywhere(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        return !url.path.contains("/.Trash/")
    }

    nonisolated static func pkgReceipts() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--pkgs"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.hasPrefix("com.apple.") }
    }

    /// 크기와, 안쪽 파일까지 포함한 가장 최근 수정 시각 (한 번 훑으면서 같이 구한다)
    nonisolated static func sizeAndNewestModification(_ url: URL) -> (Int64, Date?) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, nil) }
        var newest = values.contentModificationDate
        guard values.isDirectory == true else { return (Int64(values.totalFileAllocatedSize ?? 0), newest) }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let file = enumerator?.nextObject() as? URL {
            let v = try? file.resourceValues(forKeys: keys)
            total += Int64(v?.totalFileAllocatedSize ?? 0)
            if let date = v?.contentModificationDate, date > (newest ?? .distantPast) { newest = date }
        }
        return (total, newest)
    }

    /// 실행 중이면 정상 종료를 요청하고 최대 5초 기다린다
    static func quit(_ bundleID: String) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(200))
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return true }
        }
        return false
    }

    /// 사용자 백그라운드 항목은 지우기 전에 내린다 (안 내리면 로그아웃 전까지 계속 실행됨)
    static func unloadLaunchAgents(_ items: [LeftoverItem]) async {
        let home = NSHomeDirectory()
        let agents = items.filter { $0.kind == .launchAgent && $0.url.path.hasPrefix(home) }
        guard !agents.isEmpty else { return }
        await Task.detached {
            for item in agents {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["bootout", "gui/\(getuid())", item.url.path]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
            }
        }.value
    }
}

/// Finder에게 휴지통으로 옮겨 달라고 부탁한다 — "되돌려 놓기"가 되고, 관리자 권한이 필요한 항목은 Finder가 직접 암호를 묻는다.
/// 경로는 스크립트 문자열에 끼워 넣지 않고 인수로 넘긴다 (파일 이름으로 스크립트가 조작되지 않게).
enum FinderTrash {
    private static let script = """
    on run argv
        set targets to {}
        repeat with p in argv
            set end of targets to (POSIX file (contents of p))
        end repeat
        tell application "Finder" to delete targets
    end run
    """

    /// 옮기지 못한 경로를 돌려준다
    static func move(_ urls: [URL]) async -> [URL] {
        await Task.detached { runBlocking(urls) }.value
    }

    private static func runBlocking(_ urls: [URL]) -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + urls.map(\.path)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        if (try? process.run()) != nil {
            // 관리자 암호 창에 답할 시간까지 2분
            if done.wait(timeout: .now() + 120) == .timedOut { process.terminate() }
        }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
