import AppKit
import CoreServices
import PolyMacCore

@MainActor
public final class OrganizeModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "organize",
        displayName: ("다운로드 폴더 자동 정리", "Downloads Auto-Organize"),
        summary: ("규칙에 따라 새로 받은 파일을 옮기고 이름 바꾸기", "Move and rename new downloads by your rules"),
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
    /// 백그라운드 검사가 도는 중이면 새 요청은 끝난 뒤 한 번 더 돌린다 (겹쳐 돌지 않게)
    private var isScanning = false
    private var rescanRequested = false
    private var observer: NSObjectProtocol?

    private var settingsURL: URL { OrganizeStore.url }
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
        // 환경 설정 › 자동 정리에서 저장하면 다시 불러온다
        observer = NotificationCenter.default.addObserver(forName: OrganizeStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(announce: false) }
        }
        if settings.dryRun {
            context.toast(L("자동 정리: 미리보기 모드로 켜졌습니다\n실제로 옮기지 않고 정리 기록에만 남깁니다", "Auto-organize is on in preview mode\nNothing is moved; actions are only logged"), duration: 4)
        }
    }

    public func deactivate() {
        watcher?.stop()
        watcher = nil
        hourly?.invalidate()
        hourly = nil
        pendingRun?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        settings.isEnabled = false
        saveSettings()
    }

    public func menuItems() -> [NSMenuItem] {
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            return i
        }
        let preview = item(L("미리보기 모드 (실제로 옮기지 않음)", "Preview Mode (don't move files)"), #selector(toggleDryRun))
        preview.state = settings.dryRun ? .on : .off
        let enabledRules = settings.rules.filter(\.isEnabled).count
        let info = NSMenuItem(title: L("켜진 규칙 \(enabledRules)개 / 전체 \(settings.rules.count)개", "\(enabledRules) of \(settings.rules.count) rules on"), action: nil, keyEquivalent: "")
        info.isEnabled = false
        let undo = item(L("마지막 정리 되돌리기 (\(lastBatch.count)건)", "Undo Last Run (\(lastBatch.count))"), #selector(undoLast))
        undo.isEnabled = !lastBatch.isEmpty
        return [
            info,
            preview,
            item(L("지금 정리 실행", "Run Now"), #selector(runNow)),
            undo,
            .separator(),
            item(L("규칙 편집…", "Edit Rules…"), #selector(openEditor)),
            item(L("규칙 파일(JSON) 편집…", "Edit Rules File (JSON)…"), #selector(openRules)),
            item(L("규칙 파일 다시 불러오기", "Reload Rules File"), #selector(reloadRules)),
            item(L("정리 기록 보기", "Show Log"), #selector(openLog)),
        ]
    }

    // MARK: - 설정

    private func loadSettings() throws {
        if !FileManager.default.fileExists(atPath: settingsURL.path) {
            settings = OrganizeSettings()
            saveSettings() // 처음: 프리셋(모두 꺼짐)과 미리보기 모드로 파일 생성
            return
        }
        settings = try OrganizeStore.load()
    }

    private func saveSettings() {
        do {
            try OrganizeStore.save(settings, notify: false)
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

    /// 규칙에 걸린 파일 하나와 그 계획. 검사할 때의 크기·수정 시각·파일 번호를 같이 들고 있다가
    /// 실제로 옮기기 직전에 다시 비교한다.
    struct Plan: Sendable {
        let path: String
        let name: String
        let steps: [PlannedStep]
        let stamp: FileStamp
    }

    struct FileStamp: Equatable, Sendable {
        let size: Int64
        let modifiedAt: Date?
        let fileNumber: Int

        init?(path: String) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            modifiedAt = attrs[.modificationDate] as? Date
            fileNumber = (attrs[.systemFileNumber] as? NSNumber)?.intValue ?? 0
        }
    }

    /// 감시 폴더에서 규칙에 걸리는 파일과 그 계획. 디스크·Spotlight를 읽으므로 백그라운드에서 부른다.
    nonisolated static func pendingPlans(settings: OrganizeSettings, now: Date = Date()) -> [Plan] {
        let needs = RuleEngine.needs(settings)
        var plans: [Plan] = []
        for folder in settings.watchedFolders where folder.isEnabled {
            let dir = NSString(string: folder.path).expandingTildeInPath
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = dir + "/" + name
                var isDirectory: ObjCBool = false
                // 폴더(.app 번들 포함)는 건드리지 않는다
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
                      let stamp = FileStamp(path: path)
                else { continue }
                let steps = RuleEngine.plan(for: facts(path: path, name: name, needs: needs), settings: settings, now: now)
                if !steps.isEmpty { plans.append(Plan(path: path, name: name, steps: steps, stamp: stamp)) }
            }
        }
        return plans
    }

    /// 검사는 백그라운드에서, 결과 처리는 메인에서. 검사 중에 또 요청이 오면 끝난 뒤 한 번만 다시 돈다.
    private func scan(_ completion: @escaping @MainActor ([Plan]) -> Void) {
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        let snapshot = settings
        Task.detached(priority: .utility) {
            let plans = OrganizeModule.pendingPlans(settings: snapshot)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanning = false
                completion(plans)
                if self.rescanRequested {
                    self.rescanRequested = false
                    self.scheduleRun(after: 1)
                }
            }
        }
    }

    /// 자동 실행(감시·1시간마다). 미리보기 모드면 기록만 남긴다.
    private func run() {
        scan { [weak self] plans in
            guard let self else { return }
            if self.settings.dryRun {
                var previewCount = 0
                for plan in plans {
                    for step in plan.steps where self.previewed.insert(plan.path + "|" + step.ruleID.uuidString).inserted {
                        self.log(L("[미리보기] \(plan.name) ← '\(step.ruleName)': \(step.actions.map(Self.describe).joined(separator: ", "))", "[preview] \(plan.name) ← '\(step.ruleName)': \(step.actions.map(Self.describe).joined(separator: ", "))"))
                        previewCount += 1
                    }
                }
                if previewCount > 0 {
                    self.context.toast(L("자동 정리 미리보기: \(previewCount)건\n메뉴 › 정리 기록 보기에서 확인하세요", "Auto-organize preview: \(previewCount) item(s)\nSee menu › Show Log"))
                }
            } else {
                self.executeAll(plans)
            }
        }
    }

    private func executeAll(_ plans: [Plan]) {
        var batch: [HistoryEntry] = []
        var skipped = 0
        for plan in plans {
            // 검사한 뒤에 바뀐 파일(복사·덮어쓰기·수정 저장 중)은 이번엔 건드리지 않고 나중에 다시 본다
            guard FileStamp(path: plan.path) == plan.stamp else {
                skipped += 1
                log(L("[건너뜀] \(plan.name): 검사한 뒤에 바뀌었거나 아직 쓰는 중이라 다음에 다시 확인", "[skipped] \(plan.name): changed since the check or still being written; will retry"))
                continue
            }
            batch += execute(plan.steps, path: plan.path)
        }
        if skipped > 0 { scheduleRun(after: settings.settleDelay + 1) }
        guard !batch.isEmpty else { return }
        lastBatch = batch
        context.toast(L("자동 정리: \(batch.count)건 처리했습니다\n되돌리려면 메뉴 › 마지막 정리 되돌리기", "Auto-organize: processed \(batch.count) item(s)\nTo undo: menu › Undo Last Run"))
    }

    /// 미리보기 모드에서 "지금 정리 실행": 무엇을 할지 보여주고, 확인하면 이번 한 번만 실제로 정리한다.
    private func confirmPreviewRun(_ plans: [Plan]) {
        guard !plans.isEmpty else {
            context.toast(L("정리할 파일이 없습니다\n켜진 규칙에 맞는 파일이 감시 폴더에 없습니다", "Nothing to organize\nNo file in the watched folders matches an enabled rule"))
            return
        }
        for plan in plans {
            for step in plan.steps {
                log(L("[미리보기] \(plan.name) ← '\(step.ruleName)': \(step.actions.map(Self.describe).joined(separator: ", "))", "[preview] \(plan.name) ← '\(step.ruleName)': \(step.actions.map(Self.describe).joined(separator: ", "))"))
            }
        }
        let shown = 15
        var lines = plans.prefix(shown).map { plan in
            "• \(plan.name)\n    → " + plan.steps.flatMap(\.actions).map(Self.describe).joined(separator: ", ")
        }
        if plans.count > shown { lines.append(L("… 외 \(plans.count - shown)개 (정리 기록에 전체)", "… and \(plans.count - shown) more (full list in the log)")) }

        let alert = NSAlert()
        alert.messageText = L("파일 \(plans.count)개를 정리할까요?", "Organize \(plans.count) file(s)?")
        alert.informativeText = L("미리보기 모드라 아직 옮기지 않았습니다. \"정리하기\"를 누르면 이번 한 번만 실제로 정리하고, 미리보기 모드는 그대로 둡니다. 정리한 뒤에는 메뉴 › 마지막 정리 되돌리기로 되돌릴 수 있습니다.",
                                  "Preview mode is on, so nothing has moved yet. \"Organize\" runs it for real this once and keeps preview mode on. You can undo with menu › Undo Last Run.")
        let list = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 10))
        list.string = lines.joined(separator: "\n")
        list.isEditable = false
        list.drawsBackground = false
        list.font = .systemFont(ofSize: 12)
        list.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: min(220, CGFloat(lines.count) * 34 + 8)))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = list
        list.frame.size.width = scroll.contentSize.width
        list.sizeToFit()
        alert.accessoryView = scroll
        alert.addButton(withTitle: L("정리하기", "Organize"))
        alert.addButton(withTitle: L("취소", "Cancel"))
        NSApp.activate()
        alert.window.orderFrontRegardless()
        guard alert.runModal() == .alertFirstButtonReturn else {
            context.toast(L("정리하지 않았습니다\n미리보기 결과는 정리 기록에 남겼습니다", "Nothing was moved\nThe preview was written to the log"))
            return
        }
        log(L("[수동 실행] 미리보기 모드에서 확인 후 \(plans.count)개 정리", "[manual run] organizing \(plans.count) file(s) after confirmation in preview mode"))
        executeAll(plans)
        if lastBatch.isEmpty { context.toast(L("정리하지 못했습니다\n정리 기록에서 이유를 확인하세요", "Nothing was organized\nSee the log for details")) }
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
                        log(L("[이동] \(current) → \(dest)  ('\(step.ruleName)')", "[move] \(current) → \(dest)  ('\(step.ruleName)')"))
                        current = dest
                    case .copy(let to):
                        let dir = try safeDirectory(to)
                        try FileOps.makeDirectories(dir)
                        let dest = FileOps.uniquePath(directory: dir, name: name(current))
                        try FileOps.copy(current, to: dest)
                        done.append(HistoryEntry(kind: .copied, from: current, to: dest))
                        log(L("[복사] \(current) → \(dest)  ('\(step.ruleName)')", "[copy] \(current) → \(dest)  ('\(step.ruleName)')"))
                    case .rename(let newName):
                        guard !newName.contains("/"), newName != "..", !newName.isEmpty else {
                            throw ModuleError(L("잘못된 이름: \(newName)", "Invalid name: \(newName)"))
                        }
                        let dir = (current as NSString).deletingLastPathComponent
                        let dest = FileOps.uniquePath(directory: dir, name: newName)
                        try FileOps.move(current, to: dest)
                        done.append(HistoryEntry(kind: .moved, from: current, to: dest))
                        log(L("[이름 변경] \(current) → \(dest)  ('\(step.ruleName)')", "[rename] \(current) → \(dest)  ('\(step.ruleName)')"))
                        current = dest
                    case .trash:
                        var result: NSURL?
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: current), resultingItemURL: &result)
                        done.append(HistoryEntry(kind: .trashed, from: current, to: result?.path ?? ""))
                        log(L("[휴지통] \(current)  ('\(step.ruleName)')", "[trash] \(current)  ('\(step.ruleName)')"))
                        return done
                    case .addTag(let tag):
                        let url = URL(fileURLWithPath: current) as NSURL
                        var existing: AnyObject?
                        try? url.getResourceValue(&existing, forKey: .tagNamesKey)
                        var tags = existing as? [String] ?? []
                        if !tags.contains(tag) {
                            tags.append(tag)
                            try url.setResourceValue(tags, forKey: .tagNamesKey)
                            log(L("[태그] \(current) +\(tag)  ('\(step.ruleName)')", "[tag] \(current) +\(tag)  ('\(step.ruleName)')"))
                        }
                    case .notify:
                        let key = current + "|notify|" + step.ruleID.uuidString
                        if previewed.insert(key).inserted {
                            log(L("[알림] \(current)  ('\(step.ruleName)')", "[notify] \(current)  ('\(step.ruleName)')"))
                            context.toast(L("정리 후보: \(name(current))\n('\(step.ruleName)')", "To organize: \(name(current))\n('\(step.ruleName)')"))
                        }
                    }
                }
            }
        } catch {
            log(L("[실패] \(current): \(error.localizedDescription)", "[failed] \(current): \(error.localizedDescription)"))
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
            throw ModuleError(L("홈 폴더 밖으로는 옮기지 않습니다: \(expanded)", "Won't move files outside your home folder: \(expanded)"))
        }
        return expanded
    }

    // MARK: - 메뉴 동작

    @objc private func toggleDryRun() {
        settings.dryRun.toggle()
        previewed.removeAll()
        saveSettings()
        context.toast(settings.dryRun ? L("미리보기 모드: 옮기지 않고 기록만 합니다", "Preview mode: actions are logged, nothing is moved") : L("자동 정리가 실제로 동작합니다", "Auto-organize now moves files for real"))
        if !settings.dryRun { scheduleRun(after: 1) }
    }

    @objc private func runNow() {
        previewed.removeAll()
        scan { [weak self] plans in
            guard let self else { return }
            if self.settings.dryRun {
                self.confirmPreviewRun(plans)
                return
            }
            guard !plans.isEmpty else {
                self.context.toast(L("정리할 파일이 없습니다", "Nothing to organize"))
                return
            }
            self.lastBatch = []
            self.executeAll(plans)
        }
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
                log(L("[되돌리기] \(entry.to) → \(entry.from)", "[undo] \(entry.to) → \(entry.from)"))
            } catch {
                log(L("[되돌리기 실패] \(entry.to): \(error.localizedDescription)", "[undo failed] \(entry.to): \(error.localizedDescription)"))
            }
        }
        lastBatch.removeAll()
        context.toast(L("\(restored)건을 되돌렸습니다", "Restored \(restored) item(s)"))
    }

    /// 환경 설정 › 자동 정리 탭을 연다
    @objc private func openEditor() {
        context.openSettings(tab: "organize")
    }

    @objc private func openRules() {
        OrganizeStore.openJSON()
    }

    @objc private func reloadRules() {
        reload(announce: true)
    }

    private func reload(announce: Bool) {
        do {
            try loadSettings()
            settings.isEnabled = true
            saveSettings()
            previewed.removeAll()
            startWatching()
            if announce {
                context.toast(L("규칙을 다시 불러왔습니다 (켜진 규칙 \(settings.rules.filter(\.isEnabled).count)개)", "Rules reloaded (\(settings.rules.filter(\.isEnabled).count) on)"))
            }
            scheduleRun(after: 1)
        } catch {
            context.toast(error.localizedDescription, duration: 5)
        }
    }

    @objc private func openLog() {
        if !FileOps.exists(logURL.path) { log(L("정리 기록 시작", "Log started")) }
        NSWorkspace.shared.open(logURL)
    }

    // MARK: - 보조

    private func log(_ line: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime])
        AppPaths.appendLine("\(stamp)  \(line)", to: logURL)
    }

    private static func describe(_ action: Action) -> String {
        switch action {
        case .move(let to): return L("이동 → \(to)", "move → \(to)")
        case .copy(let to): return L("복사 → \(to)", "copy → \(to)")
        case .rename(let name): return L("이름 → \(name)", "rename → \(name)")
        case .trash: return L("휴지통", "trash")
        case .addTag(let name): return L("태그 +\(name)", "tag +\(name)")
        case .notify: return L("알림", "notify")
        }
    }

    /// Finder는 복사하는 동안 생성일을 1984-01-24로 두었다가 끝나면 원래대로 바꾼다
    private nonisolated static let finderCopyMarker = Date(timeIntervalSince1970: 443_779_200) // 1984-01-24

    /// 디스크·Spotlight에서 규칙 평가에 필요한 정보를 읽는다. 켜진 규칙이 안 쓰는 정보(needs)는 읽지 않는다.
    nonisolated static func facts(path: String, name: String, needs: RuleEngine.Needs = .init(spotlight: true, duplicate: true)) -> FileFacts {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey])
        var lastUsed: Date?
        var sources: [String] = []
        if needs.spotlight, let item = MDItemCreate(kCFAllocatorDefault, path as CFString) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            sources = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String] ?? []
        }
        let size = Int64(values?.fileSize ?? 0)
        let isBusy = values?.creationDate.map { abs($0.timeIntervalSince(finderCopyMarker)) < 86_400 } ?? false
        return FileFacts(
            name: name,
            size: size,
            addedAt: values?.addedToDirectoryDate ?? values?.creationDate ?? Date(),
            lastOpenedAt: lastUsed,
            sourceURLs: sources,
            isDuplicate: needs.duplicate && !isBusy && isDuplicate(path: path, name: name, size: size),
            modifiedAt: values?.contentModificationDate,
            isBusy: isBusy
        )
    }

    /// "이름 (1).pdf"처럼 번호가 붙었고, 같은 폴더의 원래 파일과 크기·내용이 같으면 중복
    nonisolated static func isDuplicate(path: String, name: String, size: Int64) -> Bool {
        guard let original = DuplicateName.original(of: name) else { return false }
        let other = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(original)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: other),
              attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.int64Value == size
        else { return false }
        return FileManager.default.contentsEqual(atPath: path, andPath: other)
    }
}
