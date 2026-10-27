import AppKit
import CoreServices
import PolyMacCore

@MainActor
public final class OrganizeModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "organize",
        displayName: "다운로드 폴더 자동 정리",
        permissions: [.filesAndFolders],
        enabledByDefault: false
    )

    /// 실행한 동작 하나. 되돌리기에 쓴다.
    private struct HistoryEntry {
        enum Kind { case moved, copied, trashed }
        let kind: Kind
        let from: String
        let to: String
    }

    private let context: ModuleContext
    private var settings = OrganizeSettings()
    private var watcher: FolderWatcher?
    private var hourly: Timer?
    private var pendingRun: DispatchWorkItem?
    private var previewed = Set<String>()
    private var lastBatch: [HistoryEntry] = []

    private var settingsURL: URL { context.dataDirectory.appendingPathComponent("organize.json") }
    private var logURL: URL { context.dataDirectory.appendingPathComponent("organize-log.txt") }

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        try loadSettings()
        settings.isEnabled = true
        saveSettings()
        startWatching()
        // "N일 지남" 조건은 파일 변화 없이도 성립하므로 1시간마다 한 번 확인
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.run() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        hourly = timer
        scheduleRun(after: 2)
        if settings.dryRun {
            context.toast("자동 정리: 미리보기 모드로 켜졌습니다\n실제로 옮기지 않고 정리 기록에만 남깁니다", duration: 4)
        }
    }

    public func deactivate() {
        watcher?.stop()
        watcher = nil
        hourly?.invalidate()
        hourly = nil
        pendingRun?.cancel()
        settings.isEnabled = false
        saveSettings()
    }

    public func menuItems() -> [NSMenuItem] {
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            return i
        }
        let preview = item("미리보기 모드 (실제로 옮기지 않음)", #selector(toggleDryRun))
        preview.state = settings.dryRun ? .on : .off
        let enabledRules = settings.rules.filter(\.isEnabled).count
        let info = NSMenuItem(title: "켜진 규칙 \(enabledRules)개 / 전체 \(settings.rules.count)개", action: nil, keyEquivalent: "")
        info.isEnabled = false
        let undo = item("마지막 정리 되돌리기 (\(lastBatch.count)건)", #selector(undoLast))
        undo.isEnabled = !lastBatch.isEmpty
        return [
            info,
            preview,
            item("지금 정리 실행", #selector(runNow)),
            undo,
            .separator(),
            item("규칙 파일 편집…", #selector(openRules)),
            item("규칙 다시 불러오기", #selector(reloadRules)),
            item("정리 기록 보기", #selector(openLog)),
        ]
    }

    // MARK: - 설정

    private func loadSettings() throws {
        guard let data = try? Data(contentsOf: settingsURL) else {
            saveSettings() // 처음: 프리셋(모두 꺼짐)과 미리보기 모드로 파일 생성
            return
        }
        let decoded: OrganizeSettings
        do {
            decoded = try JSONDecoder().decode(OrganizeSettings.self, from: data)
        } catch {
            // 사용자가 고친 파일을 덮어쓰지 않는다
            throw ModuleError("규칙 파일을 읽지 못했습니다 (organize.json): \(error.localizedDescription)")
        }
        guard decoded.schemaVersion <= OrganizeSettings.currentSchemaVersion else {
            throw ModuleError("규칙 파일이 더 새 버전의 PolyMac에서 만들어졌습니다. 앱을 업데이트하세요.")
        }
        settings = decoded
    }

    private func saveSettings() {
        let encoder = JSONEncoder()
        // 키 순서를 고정해 사용자가 편집할 때 매번 같은 모양이 되게
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        do {
            try AppPaths.writePrivate(try encoder.encode(settings), to: settingsURL)
        } catch {
            context.logger.error("organize settings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startWatching() {
        watcher?.stop()
        let paths = settings.watchedFolders.filter(\.isEnabled).map { NSString(string: $0.path).expandingTildeInPath }
        let watcher = FolderWatcher(paths: paths) { [weak self] _ in
            guard let self else { return }
            self.scheduleRun(after: self.settings.settleDelay + 1)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func scheduleRun(after delay: TimeInterval) {
        pendingRun?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.run() }
        }
        pendingRun = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - 실행

    private func run() {
        let now = Date()
        var batch: [HistoryEntry] = []
        var previewCount = 0
        for folder in settings.watchedFolders where folder.isEnabled {
            let dir = NSString(string: folder.path).expandingTildeInPath
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = dir + "/" + name
                var isDirectory: ObjCBool = false
                // 폴더(.app 번들 포함)는 건드리지 않는다
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                let steps = RuleEngine.plan(for: Self.facts(path: path, name: name), settings: settings, now: now)
                guard !steps.isEmpty else { continue }

                if settings.dryRun {
                    for step in steps where previewed.insert(path + "|" + step.ruleID.uuidString).inserted {
                        log("[미리보기] \(name) ← '\(step.ruleName)': \(step.actions.map(Self.describe).joined(separator: ", "))")
                        previewCount += 1
                    }
                } else {
                    batch += execute(steps, path: path)
                }
            }
        }
        if previewCount > 0 {
            context.toast("자동 정리 미리보기: \(previewCount)건\n메뉴 › 정리 기록 보기에서 확인하세요")
        }
        if !batch.isEmpty {
            lastBatch = batch
            context.toast("자동 정리: \(batch.count)건 처리했습니다")
        }
    }

    private func execute(_ steps: [PlannedStep], path: String) -> [HistoryEntry] {
        var current = path
        var done: [HistoryEntry] = []
        let name = { (p: String) in (p as NSString).lastPathComponent }
        do {
            for step in steps {
                for action in step.actions {
                    switch action {
                    case .move(let to):
                        let dir = try safeDirectory(to)
                        try FileOps.makeDirectories(dir)
                        let dest = FileOps.uniquePath(directory: dir, name: name(current))
                        try FileOps.move(current, to: dest)
                        done.append(HistoryEntry(kind: .moved, from: current, to: dest))
                        log("[이동] \(current) → \(dest)  ('\(step.ruleName)')")
                        current = dest
                    case .copy(let to):
                        let dir = try safeDirectory(to)
                        try FileOps.makeDirectories(dir)
                        let dest = FileOps.uniquePath(directory: dir, name: name(current))
                        try FileOps.copy(current, to: dest)
                        done.append(HistoryEntry(kind: .copied, from: current, to: dest))
                        log("[복사] \(current) → \(dest)  ('\(step.ruleName)')")
                    case .rename(let newName):
                        guard !newName.contains("/"), newName != "..", !newName.isEmpty else {
                            throw ModuleError("잘못된 이름: \(newName)")
                        }
                        let dir = (current as NSString).deletingLastPathComponent
                        let dest = FileOps.uniquePath(directory: dir, name: newName)
                        try FileOps.move(current, to: dest)
                        done.append(HistoryEntry(kind: .moved, from: current, to: dest))
                        log("[이름 변경] \(current) → \(dest)  ('\(step.ruleName)')")
                        current = dest
                    case .trash:
                        var result: NSURL?
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: current), resultingItemURL: &result)
                        done.append(HistoryEntry(kind: .trashed, from: current, to: result?.path ?? ""))
                        log("[휴지통] \(current)  ('\(step.ruleName)')")
                        return done
                    case .addTag(let tag):
                        let url = URL(fileURLWithPath: current) as NSURL
                        var existing: AnyObject?
                        try? url.getResourceValue(&existing, forKey: .tagNamesKey)
                        var tags = existing as? [String] ?? []
                        if !tags.contains(tag) {
                            tags.append(tag)
                            try url.setResourceValue(tags, forKey: .tagNamesKey)
                            log("[태그] \(current) +\(tag)  ('\(step.ruleName)')")
                        }
                    case .notify:
                        let key = current + "|notify|" + step.ruleID.uuidString
                        if previewed.insert(key).inserted {
                            log("[알림] \(current)  ('\(step.ruleName)')")
                            context.toast("정리 후보: \(name(current))\n('\(step.ruleName)')")
                        }
                    }
                }
            }
        } catch {
            log("[실패] \(current): \(error.localizedDescription)")
            context.logger.error("organize action failed: \(error.localizedDescription, privacy: .public)")
        }
        return done
    }

    /// 템플릿을 풀어 만든 폴더가 홈 폴더 밖이면 거부한다 (docs/SECURITY.md 4).
    private func safeDirectory(_ template: String) throws -> String {
        let home = (NSHomeDirectory() as NSString).resolvingSymlinksInPath
        let expanded = (NSString(string: template).expandingTildeInPath as NSString).standardizingPath
        // 이미 있는 부분까지 심볼릭 링크를 풀어서 확인
        var probe = expanded
        while !FileOps.exists(probe), probe != "/" { probe = (probe as NSString).deletingLastPathComponent }
        let resolvedExisting = (probe as NSString).resolvingSymlinksInPath
        guard expanded.hasPrefix(home + "/"), resolvedExisting == home || resolvedExisting.hasPrefix(home + "/") else {
            throw ModuleError("홈 폴더 밖으로는 옮기지 않습니다: \(expanded)")
        }
        return expanded
    }

    // MARK: - 메뉴 동작

    @objc private func toggleDryRun() {
        settings.dryRun.toggle()
        previewed.removeAll()
        saveSettings()
        context.toast(settings.dryRun ? "미리보기 모드: 옮기지 않고 기록만 합니다" : "자동 정리가 실제로 동작합니다")
        if !settings.dryRun { scheduleRun(after: 1) }
    }

    @objc private func runNow() {
        previewed.removeAll()
        run()
        if settings.dryRun == false, lastBatch.isEmpty { context.toast("정리할 파일이 없습니다") }
    }

    @objc private func undoLast() {
        var restored = 0
        for entry in lastBatch.reversed() {
            do {
                switch entry.kind {
                case .moved, .trashed:
                    guard !entry.to.isEmpty else { continue }
                    let dir = (entry.from as NSString).deletingLastPathComponent
                    let dest = FileOps.uniquePath(directory: dir, name: (entry.from as NSString).lastPathComponent)
                    try FileOps.move(entry.to, to: dest)
                case .copied:
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: entry.to), resultingItemURL: nil)
                }
                restored += 1
                log("[되돌리기] \(entry.to) → \(entry.from)")
            } catch {
                log("[되돌리기 실패] \(entry.to): \(error.localizedDescription)")
            }
        }
        lastBatch.removeAll()
        context.toast("\(restored)건을 되돌렸습니다")
    }

    @objc private func openRules() {
        NSWorkspace.shared.open([settingsURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func reloadRules() {
        do {
            try loadSettings()
            settings.isEnabled = true
            previewed.removeAll()
            startWatching()
            context.toast("규칙을 다시 불러왔습니다 (켜진 규칙 \(settings.rules.filter(\.isEnabled).count)개)")
            scheduleRun(after: 1)
        } catch {
            context.toast(error.localizedDescription, duration: 5)
        }
    }

    @objc private func openLog() {
        if !FileOps.exists(logURL.path) { log("정리 기록 시작") }
        NSWorkspace.shared.open(logURL)
    }

    // MARK: - 보조

    private func log(_ line: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime])
        AppPaths.appendLine("\(stamp)  \(line)", to: logURL)
    }

    private static func describe(_ action: Action) -> String {
        switch action {
        case .move(let to): return "이동 → \(to)"
        case .copy(let to): return "복사 → \(to)"
        case .rename(let name): return "이름 → \(name)"
        case .trash: return "휴지통"
        case .addTag(let name): return "태그 +\(name)"
        case .notify: return "알림"
        }
    }

    /// 디스크·Spotlight에서 규칙 평가에 필요한 정보를 읽는다.
    static func facts(path: String, name: String) -> FileFacts {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .addedToDirectoryDateKey, .creationDateKey])
        var lastUsed: Date?
        var sources: [String] = []
        if let item = MDItemCreate(kCFAllocatorDefault, path as CFString) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            sources = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String] ?? []
        }
        return FileFacts(
            name: name,
            size: Int64(values?.fileSize ?? 0),
            addedAt: values?.addedToDirectoryDate ?? values?.creationDate ?? Date(),
            lastOpenedAt: lastUsed,
            sourceURLs: sources
        )
    }
}
