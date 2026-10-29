import AppKit
import Carbon.HIToolbox
import CryptoKit
import PolyMacCore

@MainActor
public final class ClipboardModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "clipboard",
        displayName: ("클립보드 히스토리", "Clipboard History"),
        summary: ("복사한 글·이미지를 기억했다가 다시 붙여넣기", "Remember copied text and images and paste them again"),
        permissions: []
    )

    /// 보관 개수 선택지 (고정 항목은 세지 않음)
    static let capacityChoices = [50, 100, 200, 500, 1000]
    private static let capacityKey = "clipboard.maxItems"
    /// 보관 기간 선택지 (일, 0 = 기간 제한 없음). 기본 7일.
    static let retentionChoices = [1, 3, 7, 30, 0]
    private static let retentionKey = "clipboard.retentionDays"

    private let context: ModuleContext
    private var items: [ClipboardItem] = []
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var isPaused = false
    /// 이보다 큰 텍스트는 목록 파일(JSON) 대신 별도 파일에 전체를 저장하고 목록엔 앞부분만 둔다
    private let inlineTextBytes = 64 * 1024
    /// 텍스트 한 항목 최대 크기 — 긴 로그도 담되, 실수로 거대한 데이터를 복사했을 때 디스크를 채우지 않게
    private let maxTextBytes = 20 * 1024 * 1024
    /// 큰 텍스트에서 목록에 남기는 앞부분 (검색·미리보기용)
    private let previewCharacters = 4000
    /// 이미지 한 장 최대 크기 (원본 데이터 기준)
    private let maxImageBytes = 30 * 1024 * 1024
    private var pendingSave: DispatchWorkItem?
    /// 기록 파일 봉인 (키는 키체인). nil이면 키를 못 읽은 것 — 디스크에 쓰지도 읽지도 않고 메모리에만 둔다
    private var store: SealedFiles?
    private static let sealedMigrationKey = "clipboard.sealedFiles"
    private let ioQueue = DispatchQueue(label: "dev.polymac.clipboard.io", qos: .utility)

    private var storeURL: URL { context.dataDirectory.appendingPathComponent("clipboard.json") }
    var imageDirectory: URL {
        let url = context.dataDirectory.appendingPathComponent("clipboard-images", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return url
    }

    var textDirectory: URL {
        let url = context.dataDirectory.appendingPathComponent("clipboard-texts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return url
    }

    private var capacity: Int {
        let value = UserDefaults.standard.integer(forKey: Self.capacityKey)
        return value > 0 ? value : 200
    }

    private var retentionDays: Int {
        UserDefaults.standard.object(forKey: Self.retentionKey) as? Int ?? 7
    }
    private var expiryTimer: Timer?

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        openStore()
        load()
        lastChangeCount = NSPasteboard.general.changeCount
        // macOS엔 클립보드 변경 알림이 없어 changeCount를 주기적으로 비교한다 (정수 비교 1회, docs/ARCHITECTURE.md 3)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // 보관 기간이 지난 항목은 새로 복사하지 않아도 지워지게 1시간마다 확인
        let expiry = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.didChange() }
        }
        expiry.tolerance = 600
        RunLoop.main.add(expiry, forMode: .common)
        expiryTimer = expiry
        didChange()

        context.hotkey("showHistory", KeyCombo(kVK_ANSI_V, [.shift, .command]), L("클립보드 히스토리 열기", "Open clipboard history")) { [weak self] in
            self?.showPopup()
        }
        // 창은 아직 만들지 않고 썸네일·앱 아이콘만 미리 (실행 직후를 무겁게 하지 않게 조금 뒤에)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.prepare(items: self.items, imageDirectory: self.imageDirectory, textDirectory: self.textDirectory, store: self.store)
            }
        }
    }

    public func deactivate() {
        timer?.invalidate()
        timer = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        panel.tearDown()
        context.unregisterHotkeys()
        saveNow()
    }

    public func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: L("히스토리 열기", "Open History"), action: #selector(openFromMenu), keyEquivalent: "")
        let pause = NSMenuItem(title: L("기록 일시정지", "Pause Recording"), action: #selector(togglePause), keyEquivalent: "")
        pause.state = isPaused ? .on : .off

        let capacityItem = NSMenuItem(title: L("보관 개수: \(capacity)개", "Keep: \(capacity) items"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for n in Self.capacityChoices {
            let item = NSMenuItem(title: L("\(n)개", "\(n) items"), action: #selector(setCapacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = n
            item.state = n == capacity ? .on : .off
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let note = NSMenuItem(title: L("고정한 항목은 개수에 포함되지 않습니다", "Pinned items don't count toward the limit"), action: nil, keyEquivalent: "")
        note.isEnabled = false
        sub.addItem(note)
        capacityItem.submenu = sub

        let retentionItem = NSMenuItem(title: L("보관 기간: \(Self.retentionTitle(retentionDays))", "Keep for: \(Self.retentionTitle(retentionDays))"), action: nil, keyEquivalent: "")
        let retentionMenu = NSMenu()
        for days in Self.retentionChoices {
            let item = NSMenuItem(title: Self.retentionTitle(days), action: #selector(setRetention(_:)), keyEquivalent: "")
            item.target = self
            item.tag = days
            item.state = days == retentionDays ? .on : .off
            retentionMenu.addItem(item)
        }
        retentionMenu.addItem(.separator())
        let retentionNote = NSMenuItem(title: L("기간이 지나거나 개수를 넘으면 오래된 것부터 지웁니다 (고정 항목 제외)", "Oldest items are removed past the limit or period (pinned items stay)"), action: nil, keyEquivalent: "")
        retentionNote.isEnabled = false
        retentionMenu.addItem(retentionNote)
        retentionItem.submenu = retentionMenu

        let excludeItem = NSMenuItem(title: L("기록하지 않을 앱", "Don't Record From"), action: nil, keyEquivalent: "")
        excludeItem.submenu = excludedAppsMenu()

        let imageCount = items.filter(\.isImage).count
        let stats = NSMenuItem(title: L("기록 \(items.count)개 (이미지 \(imageCount)개)", "\(items.count) items (\(imageCount) images)"), action: nil, keyEquivalent: "")
        stats.isEnabled = false
        let clear = NSMenuItem(title: L("기록 지우기 (고정 항목 제외)", "Clear History (keeps pinned)"), action: #selector(clearUnpinned), keyEquivalent: "")
        return [open, pause, capacityItem, retentionItem, excludeItem, stats, clear].map { $0.target = $0.target ?? self; return $0 }
    }

    // MARK: - 기록

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard !isPaused else { return }

        let types = pb.types ?? []
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !ClipboardPrivacy.shouldIgnore(types: types.map(\.rawValue), frontmostBundleID: front, excludedApps: excludedApps) else { return }

        // Finder에서 파일을 복사하면 이름 글자도 함께 들어오므로 파일을 먼저 본다
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            record(files: urls.map { $0.path.precomposedStringWithCanonicalMapping }, from: front)
        } else if let text = pb.string(forType: .string) {
            let bytes = text.utf8.count
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard bytes <= maxTextBytes else {
                context.logger.info("clipboard text skipped: \(bytes) bytes")
                context.toast(L("20 MB가 넘는 텍스트는 클립보드 기록에 남기지 않았습니다", "Text over 20 MB was not saved to clipboard history"))
                return
            }
            if bytes > inlineTextBytes {
                record(largeText: text, bytes: bytes, from: front)
            } else {
                record(text: text, from: front)
            }
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            guard data.count <= maxImageBytes else {
                context.logger.info("clipboard image skipped: \(data.count) bytes")
                return
            }
            record(imageData: data, from: front)
        }
    }

    private func record(files paths: [String], from app: String?) {
        if let index = items.firstIndex(where: { $0.files == paths }) {
            var item = items.remove(at: index)
            item.copiedAt = Date()
            item.sourceApp = app
            items.insert(item, at: 0)
        } else {
            items.insert(.files(paths, sourceApp: app), at: 0)
        }
        didChange()
    }

    private func record(text: String, from app: String?) {
        if let index = items.firstIndex(where: { !$0.isImage && !$0.isLargeText && !$0.isFiles && $0.text == text }) {
            var item = items.remove(at: index)
            item.copiedAt = Date()
            item.sourceApp = app
            items.insert(item, at: 0)
        } else {
            items.insert(ClipboardItem(text: text, sourceApp: app), at: 0)
        }
        didChange()
    }

    /// 긴 로그 등: 전체는 별도 파일, 목록에는 앞부분만 (해시·파일 쓰기는 백그라운드)
    private func record(largeText text: String, bytes: Int, from app: String?) {
        let directory = textDirectory
        let preview = String(text.prefix(previewCharacters))
        ioQueue.async { [weak self] in
            let data = Data(text.utf8)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let index = self.items.firstIndex(where: { $0.contentHash == hash }) {
                        var item = self.items.remove(at: index)
                        item.copiedAt = Date()
                        item.sourceApp = app
                        self.items.insert(item, at: 0)
                        self.didChange()
                        return
                    }
                    let file = UUID().uuidString + ".txt"
                    self.keep(data, at: directory.appendingPathComponent(file),
                              as: .largeText(preview: preview, file: file, bytes: bytes, hash: hash, sourceApp: app))
                }
            }
        }
    }

    /// PNG 변환·해시·파일 쓰기는 무거울 수 있어 백그라운드에서
    private func record(imageData: Data, from app: String?) {
        let directory = imageDirectory
        ioQueue.async { [weak self] in
            let hash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
            guard let rep = NSBitmapImageRep(data: imageData) else { return }
            let png = imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? imageData : (rep.representation(using: .png, properties: [:]) ?? imageData)
            let width = rep.pixelsWide, height = rep.pixelsHigh
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let index = self.items.firstIndex(where: { $0.contentHash == hash }) {
                        var item = self.items.remove(at: index)
                        item.copiedAt = Date()
                        item.sourceApp = app
                        self.items.insert(item, at: 0)
                        self.didChange()
                        return
                    }
                    let file = UUID().uuidString + ".png"
                    self.keep(png, at: directory.appendingPathComponent(file),
                              as: .image(file: file, width: width, height: height, bytes: png.count, hash: hash, sourceApp: app))
                }
            }
        }
    }

    /// 파일을 다 쓴 뒤에 목록에 넣는다 — 목록에 먼저 보이면 썸네일·미리보기가 아직 없는 파일을 읽으려다 실패한다
    private func keep(_ data: Data, at url: URL, as item: ClipboardItem) {
        guard let store else {
            context.logger.info("clipboard \(item.isImage ? "image" : "long text", privacy: .public) not kept: no storage key")
            return
        }
        let logger = context.logger
        ioQueue.async { [weak self] in
            do {
                try store.write(data, to: url)
            } catch {
                logger.error("clipboard file write failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // 쓰는 사이 같은 내용이 먼저 들어왔으면 방금 쓴 파일은 버리고 있던 항목을 맨 위로
                    if let index = self.items.firstIndex(where: { $0.contentHash == item.contentHash }) {
                        var existing = self.items.remove(at: index)
                        existing.copiedAt = Date()
                        existing.sourceApp = item.sourceApp
                        self.items.insert(existing, at: 0)
                        self.ioQueue.async { try? FileManager.default.removeItem(at: url) }
                    } else {
                        self.items.insert(item, at: 0)
                    }
                    self.didChange()
                }
            }
        }
    }

    private func didChange() {
        trim()
        scheduleSave()
        panel.update(items: items)
    }

    /// 보관 기간이 지났거나 보관 개수를 넘는 오래된 항목 삭제 (고정 항목 제외), 따로 저장한 파일도 함께 지운다
    private func trim() {
        let cutoff = retentionDays > 0 ? Date().addingTimeInterval(-Double(retentionDays) * 86_400) : nil
        var unpinned = 0
        var removed: [ClipboardItem] = []
        items.removeAll { item in
            guard !item.isPinned else { return false }
            if let cutoff, item.copiedAt < cutoff { removed.append(item); return true }
            unpinned += 1
            if unpinned > capacity { removed.append(item); return true }
            return false
        }
        if !removed.isEmpty { context.logger.info("clipboard trimmed \(removed.count) items") }
        deleteFiles(of: removed)
    }

    private func deleteFiles(of removed: [ClipboardItem]) {
        let base = context.dataDirectory
        let urls = removed.flatMap(\.storedFiles).map { base.appendingPathComponent($0) }
        guard !urls.isEmpty else { return }
        ioQueue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    // MARK: - 히스토리 창

    private let panel = ClipboardPanelController()

    private func showPopup() {
        if !panel.isPrepared { panel.prepare(items: items, imageDirectory: imageDirectory, textDirectory: textDirectory, store: store) }
        panel.show(callbacks: .init(
            choose: { [weak self] item, pasteNow in
                guard let self else { return }
                self.copyToPasteboard(item)
                if pasteNow {
                    self.pasteIntoFrontApp()
                } else if item.isImage {
                    self.context.toast(L("이미지를 클립보드에 복사했습니다", "Image copied to the clipboard"))
                } else if let files = item.files {
                    self.context.toast(L("파일 \(files.count)개를 클립보드에 넣었습니다 — Finder에서 ⌘V", "Put \(files.count) file(s) on the clipboard — ⌘V in Finder"))
                } else if item.isLargeText {
                    let size = ByteCountFormatter.string(fromByteCount: Int64(item.textBytes ?? 0), countStyle: .file)
                    self.context.toast(L("긴 텍스트 전체(\(size))를 클립보드에 복사했습니다", "Copied the full long text (\(size)) to the clipboard"))
                } else {
                    let preview = item.text.count > 60 ? String(item.text.prefix(60)) + "…" : item.text
                    self.context.toast(L("클립보드에 복사했습니다\n\(preview)", "Copied to the clipboard\n\(preview)"))
                }
            },
            togglePin: { [weak self] id in self?.togglePin(id) },
            delete: { [weak self] id in self?.delete(id) }
        ))
    }

    /// 큰 텍스트는 파일에서 전체를 읽는다
    func fullText(_ item: ClipboardItem) -> String {
        guard let file = item.textFile,
              let data = try? store?.read(textDirectory.appendingPathComponent(file)),
              let text = String(data: data, encoding: .utf8)
        else { return item.text }
        return text
    }

    private func copyToPasteboard(_ item: ClipboardItem) {
        if let paths = item.files, !paths.isEmpty {
            let present = paths.filter { FileManager.default.fileExists(atPath: $0) }
            guard !present.isEmpty else {
                context.toast(L("복사했던 파일이 더 이상 없습니다", "Those files no longer exist"))
                return
            }
            // Finder에서 ⌘V로 다시 붙여넣을 수 있게 파일로 넣는다 (다른 앱에는 경로 글자로)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(present.map { URL(fileURLWithPath: $0) as NSURL })
            return
        }
        guard let file = item.imageFile else {
            PasteboardWriter.copy(fullText(item))
            return
        }
        let url = imageDirectory.appendingPathComponent(file)
        guard let png = try? store?.read(url) else {
            context.toast(L("이미지 파일을 찾지 못했습니다", "Image file not found"))
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    /// 앞의 앱에 바로 ⌘V (⇧↩︎)
    private func pasteIntoFrontApp() {
        guard Permissions.accessibility else {
            context.toast(L("복사했습니다 — ⌘V로 붙여넣으세요\n(자동 붙여넣기는 손쉬운 사용 권한이 필요합니다)", "Copied — press ⌘V to paste\n(auto-paste needs Accessibility permission)"))
            return
        }
        // 창이 닫히고 원래 앱으로 포커스가 돌아간 뒤 ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            // Finder ⌘X 잘라내기 탭이 이 ⌘V를 "이동"으로 바꾸지 않게 표식
            down?.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.marker)
            up?.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.marker)
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        didChange()
    }

    private func delete(_ id: UUID) {
        let removed = items.filter { $0.id == id }
        items.removeAll { $0.id == id }
        deleteFiles(of: removed)
        scheduleSave()
    }

    // MARK: - 기록하지 않을 앱

    private static let excludedAppsKey = "clipboard.excludedApps"

    private var excludedApps: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.excludedAppsKey) ?? [])
    }

    private func setExcluded(_ id: String, _ on: Bool) {
        var apps = excludedApps
        if on { apps.insert(id) } else { apps.remove(id) }
        UserDefaults.standard.set(apps.sorted(), forKey: Self.excludedAppsKey)
    }

    /// 메뉴바 메뉴를 열어도 앞의 앱은 그대로라, "지금 쓰던 앱 제외"를 바로 고를 수 있다
    private func excludedAppsMenu() -> NSMenu {
        let menu = NSMenu()
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
           id != Bundle.main.bundleIdentifier, !excludedApps.contains(id), !ClipboardPrivacy.defaultIgnoredApps.contains(id) {
            let add = NSMenuItem(title: L("'\(front.localizedName ?? id)'에서 복사한 것은 기록 안 함", "Don't record copies from '\(front.localizedName ?? id)'"),
                                 action: #selector(excludeApp(_:)), keyEquivalent: "")
            add.representedObject = id
            add.target = self
            menu.addItem(add)
            menu.addItem(.separator())
        }
        let apps = excludedApps.sorted { AppInfo.name(for: $0).localizedStandardCompare(AppInfo.name(for: $1)) == .orderedAscending }
        if apps.isEmpty {
            let none = NSMenuItem(title: L("직접 제외한 앱 없음", "No apps excluded yet"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for id in apps {
            let item = NSMenuItem(title: AppInfo.name(for: id), action: #selector(includeApp(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            item.state = .on
            item.toolTip = L("눌러서 다시 기록", "Click to record again")
            item.image = AppInfo.icon(for: id).resizedForMenu()
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let note = NSMenuItem(title: L("항상 제외: 키체인 접근, 암호, 1Password, Bitwarden, 암호로 표시된 복사", "Always excluded: Keychain Access, Passwords, 1Password, Bitwarden, copies marked as concealed"),
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        return menu
    }

    @objc private func excludeApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setExcluded(id, true)
        context.toast(L("\(AppInfo.name(for: id))에서 복사한 것은 기록하지 않습니다", "Copies from \(AppInfo.name(for: id)) won't be recorded"))
    }

    @objc private func includeApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setExcluded(id, false)
        context.toast(L("\(AppInfo.name(for: id))에서 복사한 것을 다시 기록합니다", "Recording copies from \(AppInfo.name(for: id)) again"))
    }

    @objc private func openFromMenu() {
        showPopup()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        context.toast(isPaused ? L("클립보드 기록을 일시정지했습니다", "Clipboard recording paused") : L("클립보드 기록을 다시 시작합니다", "Clipboard recording resumed"))
    }

    @objc private func setCapacity(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Self.capacityKey)
        didChange()
        context.toast(L("클립보드 보관 개수: \(sender.tag)개", "Clipboard keeps \(sender.tag) items"))
    }

    private static func retentionTitle(_ days: Int) -> String {
        days == 0 ? L("제한 없음", "No limit") : L("\(days)일", "\(days) days")
    }

    @objc private func setRetention(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Self.retentionKey)
        didChange()
        context.toast(L("클립보드 보관 기간: \(Self.retentionTitle(sender.tag))", "Clipboard keeps items for: \(Self.retentionTitle(sender.tag))"))
    }

    @objc private func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        deleteFiles(of: removed)
        scheduleSave()
        context.toast(L("기록을 지웠습니다", "History cleared"))
    }

    // MARK: - 저장 (0600, 로컬만)

    /// 키체인에서 기록 암호화 키를 꺼낸다. 처음이면 만든다. 키체인이 잠겼거나 거절되면 새 키를 만들지 않는다
    /// (만들면 예전 기록을 영영 못 연다) — 이번 실행 동안은 디스크 없이 메모리에만 기록한다.
    private func openStore() {
        guard store == nil else { return }
        do {
            store = SealedFiles(key: try KeychainKey.loadOrCreate(account: "clipboard-history",
                                                                   label: L("PolyMac 클립보드 기록 암호화 키", "PolyMac clipboard history key")))
        } catch {
            context.logger.error("clipboard storage key unavailable: \(String(describing: error), privacy: .public)")
            context.toast(L("키체인에서 클립보드 기록 키를 읽지 못해, 이번에는 기록을 디스크에 저장하지 않습니다 (글자만, 종료하면 사라짐)",
                            "Could not read the clipboard history key from the keychain; history is kept in memory only this time (text only, gone on quit)"), duration: 6)
        }
    }

    private func load() {
        guard let store, let raw = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            items = try decoder.decode([ClipboardItem].self, from: try store.open(raw))
        } catch {
            // 열 수 없는 기록은 지우지 않고 옆으로 치운다 (키를 되찾으면 다시 열 수 있게)
            context.logger.error("clipboard store unreadable: \(String(describing: error), privacy: .public)")
            let aside = storeURL.deletingLastPathComponent().appendingPathComponent("clipboard.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: storeURL, to: aside)
            context.toast(L("클립보드 기록을 열 수 없어 새로 시작합니다 (예전 파일은 데이터 폴더에 남겨 둠)",
                            "Could not open the clipboard history; starting fresh (the old file is kept in the data folder)"), duration: 6)
            return
        }
        if !SealedFiles.isSealed(raw) || !UserDefaults.standard.bool(forKey: Self.sealedMigrationKey) { sealExisting() }
    }

    /// 암호화 전에 평문으로 저장된 목록·이미지·긴 텍스트를 봉인해 다시 쓴다 (한 번만)
    private func sealExisting() {
        guard let store else { return }
        let base = context.dataDirectory
        let urls = [storeURL] + items.flatMap(\.storedFiles).map { base.appendingPathComponent($0) }
        let logger = context.logger
        ioQueue.async {
            var sealed = 0, failed = 0
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                do {
                    if try store.sealInPlace(url) { sealed += 1 }
                } catch {
                    failed += 1
                }
            }
            logger.notice("clipboard files sealed=\(sealed) failed=\(failed)")
            if failed == 0 {
                DispatchQueue.main.async { UserDefaults.standard.set(true, forKey: Self.sealedMigrationKey) }
            }
        }
    }

    /// 연속으로 복사해도 1초에 한 번만, 백그라운드에서 쓴다
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let store else { return } // 키가 없으면 디스크에 쓰지 않는다 (평문으로도)
        let snapshot = items
        let url = storeURL
        let logger = context.logger
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                try store.write(try encoder.encode(snapshot), to: url)
            } catch {
                logger.error("clipboard save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension NSImage {
    /// 메뉴 항목 옆 작은 아이콘
    func resizedForMenu() -> NSImage {
        let copy = (self.copy() as? NSImage) ?? self
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}
