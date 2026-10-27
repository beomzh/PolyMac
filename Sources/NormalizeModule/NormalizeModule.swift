import AppKit
import PolyMacCore

@MainActor
public final class NormalizeModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "normalize",
        displayName: "한글 자소분리 자동 정리",
        permissions: [.filesAndFolders]
    )

    private let context: ModuleContext
    private var watcher: FolderWatcher?

    /// 감시 폴더 (바로 아래 항목만). 추가: defaults write dev.polymac.app normalize.extraFolders -array "~/Documents/받은파일"
    private var folders: [String] {
        let extra = UserDefaults.standard.stringArray(forKey: "normalize.extraFolders") ?? []
        return (["~/Downloads", "~/Desktop"] + extra).map { NSString(string: $0).expandingTildeInPath }
    }

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        let targets = folders.filter { !isExcluded($0) }
        targets.forEach(normalize)
        let watcher = FolderWatcher(paths: targets) { [weak self] changed in
            self?.handle(changed, roots: targets)
        }
        watcher.start()
        self.watcher = watcher
    }

    public func deactivate() {
        watcher?.stop()
        watcher = nil
    }

    public func menuItems() -> [NSMenuItem] {
        let names = folders.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")
        let info = NSMenuItem(title: "감시 중: \(names)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        let run = NSMenuItem(title: "지금 정리", action: #selector(runNow), keyEquivalent: "")
        run.target = self
        return [info, run]
    }

    @objc private func runNow() {
        var total = 0
        for dir in folders where !isExcluded(dir) {
            total += (try? HangulNormalizer.normalizeDirectory(dir).count) ?? 0
        }
        context.toast(total == 0 ? "자소분리된 파일명이 없습니다" : "한글 파일명 \(total)개를 정리했습니다")
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
            context.toast("한글 파일명 \(renamed.count)개를 정리했습니다")
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
