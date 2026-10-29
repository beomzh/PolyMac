import AppKit
import PolyMacCore

/// Finder 우클릭 메뉴(macOS 서비스)에서 고른 항목으로 하는 일.
/// Finder 확장 없이도 Finder가 고른 파일 목록을 직접 넘겨 주므로 자동화(AppleScript) 권한이 필요 없다.
public extension FinderModule {
    /// 고른 폴더(파일이면 그 파일이 든 폴더)에서 터미널 열기
    func openTerminal(at urls: [URL]) {
        guard let first = urls.first else { return }
        let folder = first.hasDirectoryPath || Self.isFolder(first) ? first.path : first.deletingLastPathComponent().path
        let terminal = TerminalApp.current
        do {
            try terminal.open(folder: folder)
        } catch {
            context.toast(L("\(terminal.name)을(를) 열지 못했습니다: \(error.localizedDescription)", "Could not open \(terminal.name): \(error.localizedDescription)"))
        }
    }

    /// 고른 파일·폴더를 정해 둔 에디터로. 폴더를 못 여는 앱(텍스트 편집기 등)에는 파일만 넘긴다.
    func openInEditor(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let editor = EditorApp.current
        let (open, skipped) = editor.split(urls, isFolder: { $0.hasDirectoryPath || Self.isFolder($0) })
        guard !open.isEmpty else {
            context.toast(L("\(editor.name)은(는) 폴더를 열 수 없습니다\n메뉴 › Finder 도구 › 에디터 앱에서 바꾸세요",
                            "\(editor.name) can't open folders\nChange it in the menu › Finder Tools › Editor app"), duration: 4)
            return
        }
        do {
            try editor.open(open)
            context.logger.info("opened \(open.count) item(s) in \(editor.bundleID, privacy: .public), skipped \(skipped.count) folder(s)")
            if !skipped.isEmpty {
                context.toast(L("폴더 \(skipped.count)개는 빼고 열었습니다 (\(editor.name)은(는) 폴더를 열 수 없음)",
                                "Skipped \(skipped.count) folder(s) (\(editor.name) can't open folders)"))
            }
        } catch {
            context.logger.error("editor open failed: \(error.localizedDescription, privacy: .public)")
            context.toast(L("\(editor.name)을(를) 열지 못했습니다: \(error.localizedDescription)", "Could not open \(editor.name): \(error.localizedDescription)"))
        }
    }

    /// 고른 항목의 경로를 줄마다 하나씩 (한글은 NFC로)
    func copyPaths(of urls: [URL]) {
        guard !urls.isEmpty else { return }
        let text = urls.map(\.path).joined(separator: "\n").precomposedStringWithCanonicalMapping
        PasteboardWriter.copy(text)
        context.toast(urls.count == 1 ? L("경로를 복사했습니다\n\(text)", "Path copied\n\(text)") : L("경로 \(urls.count)개를 복사했습니다", "Copied \(urls.count) paths"))
    }

    /// 고를 폴더로 옮기거나 복사한다. 같은 이름이 있으면 " 2"를 붙인다.
    func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("보내기", "Send")
        panel.message = L("\(urls.count)개 항목을 보낼 폴더를 고르세요", "Choose a folder for \(urls.count) item(s)")
        if let last = UserDefaults.standard.string(forKey: Self.lastSendFolderKey) {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        let copyBox = NSButton(checkboxWithTitle: L("복사 (원본은 그대로 두기)", "Copy (keep the originals)"), target: nil, action: nil)
        copyBox.state = UserDefaults.standard.bool(forKey: Self.sendCopiesKey) ? .on : .off
        panel.accessoryView = copyBox
        panel.isAccessoryViewDisclosed = true
        NSApp.activate()
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let copies = copyBox.state == .on
        UserDefaults.standard.set(destination.path, forKey: Self.lastSendFolderKey)
        UserDefaults.standard.set(copies, forKey: Self.sendCopiesKey)

        let context = context
        DispatchQueue.global(qos: .userInitiated).async {
            var done: [URL] = []
            var failures: [String] = []
            for url in urls {
                let target = Self.freeName(for: url.lastPathComponent, in: destination)
                do {
                    if url.standardizedFileURL == target.deletingLastPathComponent().standardizedFileURL { continue }
                    if copies {
                        try FileManager.default.copyItem(at: url, to: target)
                    } else {
                        try FileManager.default.moveItem(at: url, to: target)
                    }
                    done.append(target)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let verb = copies ? L("복사", "Copied") : L("이동", "Moved")
                    let folder = destination.lastPathComponent
                    if failures.isEmpty {
                        context.toast(L("\(done.count)개를 \(folder)(으)로 \(verb)했습니다", "\(verb) \(done.count) item(s) to \(folder)"))
                    } else {
                        context.toast(L("\(done.count)개 \(verb), \(failures.count)개 실패\n", "\(verb) \(done.count), \(failures.count) failed\n") + failures.prefix(2).joined(separator: "\n"), duration: 5)
                    }
                    if !done.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(done) }
                }
            }
        }
    }

    private static let lastSendFolderKey = "finder.sendTo.lastFolder"
    private static let sendCopiesKey = "finder.sendTo.copies"

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// "이름.txt"가 있으면 "이름 2.txt", "이름 3.txt"…
    nonisolated static func freeName(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
