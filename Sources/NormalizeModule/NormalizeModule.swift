import AppKit
import PolyMacCore

@MainActor
public final class NormalizeModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "normalize",
        displayName: ("한글 자소분리 자동 정리", "Korean Filename Fix"),
        summary: ("다운로드·데스크탑의 풀어진 한글 파일명(NFD)을 자동으로 붙이기", "Automatically fix decomposed (NFD) Korean filenames in Downloads and Desktop"),
        permissions: [.filesAndFolders]
    )

    let context: ModuleContext
    private var watcher: FolderWatcher?
    private var observer: NSObjectProtocol?
    private lazy var clipboardFix = ClipboardHangulFix { [context] message in context.logger.info("\(message, privacy: .public)") }

    /// 감시 폴더 (바로 아래 항목만) — 환경 설정 › 한글 파일명, 또는 NormalizeFolders 설명의 defaults 명령
    private var folders: [String] { NormalizeFolders.activePaths() }

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        if ClipboardHangulFix.isEnabled { clipboardFix.start() }
        startWatching()
        observer = NotificationCenter.default.addObserver(forName: NormalizeFolders.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startWatching() }
        }
    }

    private func startWatching() {
        watcher?.stop()
        watcher = nil
        let targets = folders.filter { !isExcluded($0) }
        guard !targets.isEmpty else {
            context.logger.info("normalize: no folders to watch")
            return
        }
        targets.forEach(normalize)
        let watcher = FolderWatcher(paths: targets) { [weak self] changed in
            self?.handle(changed, roots: targets)
        }
        watcher.start()
        self.watcher = watcher
        context.logger.info("normalize watching \(targets.count) folders")
    }

    public func deactivate() {
        clipboardFix.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        watcher?.stop()
        watcher = nil
    }

    public func menuItems() -> [NSMenuItem] {
        let names = folders.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")
        let info = NSMenuItem(title: L("감시 중: \(names)", "Watching: \(names)"), action: nil, keyEquivalent: "")
        info.isEnabled = false
        let run = NSMenuItem(title: L("지금 정리", "Fix Now"), action: #selector(runNow), keyEquivalent: "")
        run.target = self
        let clipboard = NSMenuItem(title: L("복사한 글자의 풀어진 한글도 붙이기", "Also Fix Decomposed Korean in Copied Text"), action: #selector(toggleClipboardFix), keyEquivalent: "")
        clipboard.target = self
        clipboard.state = ClipboardHangulFix.isEnabled ? .on : .off
        clipboard.toolTip = L("Finder 파일명 등에서 복사한 \"ㅎㅏㄴㄱㅡㄹ\"을 \"한글\"로. 비밀번호·파일 복사는 건드리지 않습니다.",
                              "Turns decomposed Korean copied from Finder names and similar into normal text. Passwords and copied files are left alone.")
        return [info, run, clipboard]
    }

    @objc private func toggleClipboardFix() {
        ClipboardHangulFix.isEnabled.toggle()
        if ClipboardHangulFix.isEnabled { clipboardFix.start() } else { clipboardFix.stop() }
        context.toast(ClipboardHangulFix.isEnabled
            ? L("복사한 글자의 풀어진 한글을 붙입니다", "Copied text: decomposed Korean will be fixed")
            : L("복사한 글자는 그대로 둡니다", "Copied text is left as is"))
    }

    @objc private func runNow() {
        var total = 0
        for dir in folders where !isExcluded(dir) {
            total += (try? HangulNormalizer.normalizeDirectory(dir).count) ?? 0
        }
        context.toast(total == 0 ? L("자소분리된 파일명이 없습니다", "No decomposed filenames found") : L("한글 파일명 \(total)개를 정리했습니다", "Fixed \(total) Korean filename(s)"))
    }

    private func handle(_ changed: [String], roots: [String]) {
        let dirs = Set(changed.flatMap { [$0, ($0 as NSString).deletingLastPathComponent] }).intersection(roots)
        dirs.forEach(normalize)
    }

    private func normalize(_ dir: String) {
        do {
            let renamed = try HangulNormalizer.normalizeDirectory(dir)
            guard !renamed.isEmpty else { return }
            context.logger.info("normalized \(renamed.count) names in \(dir, privacy: .private)")
            context.toast(L("한글 파일명 \(renamed.count)개를 정리했습니다", "Fixed \(renamed.count) Korean filename(s)"))
        } catch {
            context.logger.error("normalize failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// iCloud 등 동기화 폴더는 이름 변경이 다른 기기로 퍼지므로 건드리지 않는다 (docs/CONCEPT.md 4.8).
    private func isExcluded(_ dir: String) -> Bool {
        let values = try? URL(fileURLWithPath: dir).resourceValues(forKeys: [.isUbiquitousItemKey])
        if values?.isUbiquitousItem == true {
            context.logger.info("skip synced folder \(dir, privacy: .private)")
            return true
        }
        return false
    }
}
