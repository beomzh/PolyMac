import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PolyMacCore

@MainActor
public final class FinderModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "finder",
        displayName: ("Finder 도구", "Finder Tools"),
        summary: ("Finder에서 ⌘X 잘라내기, 터미널 열기, 에디터로 열기, 경로 복사", "Cut with ⌘X in Finder, open Terminal or an editor here, copy path"),
        permissions: [.accessibility, .automationFinder]
    )

    let context: ModuleContext
    private var keyTap: FinderKeyTap?
    /// 권한이 없어 탭을 못 만들었을 때만 도는 재시도 타이머. 권한이 생기면 멈춘다.
    private var retryTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var cutCombo: KeyCombo?
    private var pasteCombo: KeyCombo?

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        if !Permissions.accessibility { Permissions.requestAccessibility() }
        // macOS Finder엔 파일 잘라내기가 없다 (⌘X 메뉴 비활성). 기본 이동 방법인 ⌘C → ⌥⌘V를 이 두 키로 대신한다.
        context.localShortcut("cut", KeyCombo(kVK_ANSI_X, [.command]), L("Finder 파일 잘라내기", "Cut files in Finder"), note: L("Finder 안에서만 · ⌘C로 바꿔 보냄", "Finder only · sent as ⌘C")) { [weak self] combo in
            self?.cutCombo = combo
            self?.keyTap?.setShortcuts(cut: combo, paste: self?.pasteCombo)
        }
        context.localShortcut("paste", KeyCombo(kVK_ANSI_V, [.command]), L("Finder 잘라낸 파일 붙여넣기 (이동)", "Paste cut files in Finder (move)"), note: L("Finder 안에서만 · 잘라내기 뒤에만 ⌥⌘V로 바꿔 보냄", "Finder only · sent as ⌥⌘V right after a cut")) { [weak self] combo in
            self?.pasteCombo = combo
            self?.keyTap?.setShortcuts(cut: self?.cutCombo, paste: combo)
        }
        startKeyTap()
        context.hotkey("openTerminal", KeyCombo(kVK_ANSI_T, [.control, .option]), L("Finder 현재 폴더에서 터미널 열기", "Open Terminal in current Finder folder")) { [weak self] in
            self?.openTerminal()
        }
        context.hotkey("copyPaths", KeyCombo(kVK_ANSI_C, [.control, .option]), L("Finder 선택 항목 경로 복사", "Copy paths of Finder selection")) { [weak self] in
            self?.copyPaths()
        }
        context.hotkey("openEditor", KeyCombo(kVK_ANSI_E, [.control, .option]), L("Finder 선택 항목을 에디터로 열기", "Open Finder selection in editor")) { [weak self] in
            self?.openEditor()
        }
    }

    public func deactivate() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        keyTap?.stop()
        keyTap = nil
        context.unregisterHotkeys()
    }

    public func menuItems() -> [NSMenuItem] {
        let running = keyTap?.isRunning == true
        let cut = cutCombo?.display ?? L("꺼짐", "off")
        let status = NSMenuItem(title: running ? L("잘라내기(\(cut)): 켜짐", "Cut (\(cut)): on") : L("잘라내기(\(cut)): 대기 중 (손쉬운 사용 권한이 필요합니다)", "Cut (\(cut)): waiting (needs Accessibility permission)"), action: nil, keyEquivalent: "")
        status.isEnabled = false

        let terminalItem = NSMenuItem(title: L("터미널 앱: \(TerminalApp.current.name)", "Terminal app: \(TerminalApp.current.name)"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let installed = TerminalApp.installed
        for app in installed {
            let item = NSMenuItem(title: app.name, action: #selector(chooseTerminal(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleID
            item.state = app.bundleID == TerminalApp.current.bundleID ? .on : .off
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let hint = NSMenuItem(title: L("지원: ", "Supported: ") + TerminalApp.known.map(\.name).joined(separator: ", "), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        sub.addItem(hint)
        terminalItem.submenu = sub
        return [status, terminalItem, editorMenuItem()]
    }

    private func editorMenuItem() -> NSMenuItem {
        let current = EditorApp.current
        let item = NSMenuItem(title: L("에디터 앱: \(current.name)", "Editor app: \(current.name)"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        var apps = EditorApp.installedKnown
        // 직접 고른 앱도 목록에 보이게
        if !apps.contains(current) { apps.insert(current, at: 0) }
        for app in apps {
            let entry = NSMenuItem(title: app.name, action: #selector(chooseEditor(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = app.bundleID
            entry.state = app.bundleID == current.bundleID ? .on : .off
            if let url = EditorApp.appURL(app.bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            sub.addItem(entry)
        }
        sub.addItem(.separator())
        let other = NSMenuItem(title: L("다른 앱 고르기…", "Choose Another App…"), action: #selector(chooseOtherEditor), keyEquivalent: "")
        other.target = self
        sub.addItem(other)
        item.submenu = sub
        return item
    }

    @objc private func chooseEditor(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: EditorApp.defaultsKey)
        context.toast(L("에디터로 열기: \(EditorApp.current.name)", "Open in editor with: \(EditorApp.current.name)"))
    }

    @objc private func chooseOtherEditor() {
        guard let app = EditorApp.choose() else { return }
        context.toast(L("에디터로 열기: \(app.name)", "Open in editor with: \(app.name)"))
    }

    @objc private func chooseTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: TerminalApp.defaultsKey)
        context.toast(L("터미널 열기: \(TerminalApp.current.name)", "Open Terminal with: \(TerminalApp.current.name)"))
    }

    // MARK: - ⌘X 잘라내기

    private func startKeyTap() {
        let tap = FinderKeyTap { [context] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { context.toast(L("✂️ 잘라내기 — 옮길 폴더에서 ⌘V", "✂️ Cut — press ⌘V in the destination folder")) }
            }
        }
        guard tap.start() else {
            context.logger.error("event tap unavailable (accessibility not granted) — will retry")
            waitForAccessibility()
            return
        }
        keyTap = tap
        tap.setShortcuts(cut: cutCombo, paste: pasteCombo)
        // 앞에 있는 앱은 콜백 스레드에서 묻지 않고 전환 알림으로 미리 알려 준다
        tap.setFinderFrontmost(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder")
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak tap] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            tap?.setFinderFrontmost(app?.bundleIdentifier == "com.apple.finder")
        }
    }

    /// 손쉬운 사용 권한 변경 알림은 오지 않는 경우가 있어, 탭이 없을 때만 2초마다 확인한다.
    private func waitForAccessibility() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Permissions.accessibility else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.startKeyTap()
                if self.keyTap != nil { self.context.toast(L("Finder ⌘X 잘라내기가 켜졌습니다", "Finder ⌘X cut is on")) }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    // MARK: - 터미널 열기 / 경로 복사

    private func openTerminal() {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            else
                return POSIX path of (desktop as alias)
            end if
        end tell
        """
        runAppleScript(script) { [weak self] path in
            guard let self, let path, !path.isEmpty else { return }
            let terminal = TerminalApp.current
            do {
                try terminal.open(folder: path)
            } catch {
                self.context.logger.error("terminal open failed: \(error.localizedDescription, privacy: .public)")
                self.context.toast(L("\(terminal.name)을(를) 열지 못했습니다: \(error.localizedDescription)", "Could not open \(terminal.name): \(error.localizedDescription)"))
            }
        }
    }

    /// Finder에서 고른 항목 (없으면 맨 앞 창의 폴더) 경로를 줄마다 하나씩
    private static let selectionScript = """
    tell application "Finder"
        set sel to selection as alias list
        if sel is {} then
            if (count of Finder windows) = 0 then return ""
            set sel to {target of front Finder window as alias}
        end if
        set out to {}
        repeat with f in sel
            set end of out to POSIX path of f
        end repeat
    end tell
    set AppleScript's text item delimiters to linefeed
    return out as text
    """

    private func openEditor() {
        runAppleScript(Self.selectionScript) { [weak self] raw in
            guard let self else { return }
            let urls = (raw ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            guard !urls.isEmpty else {
                self.context.toast(L("열 Finder 항목이 없습니다", "No Finder items to open"))
                return
            }
            self.openInEditor(urls)
        }
    }

    private func copyPaths() {
        let script = Self.selectionScript
        runAppleScript(script) { [weak self] raw in
            guard let self else { return }
            guard let raw, !raw.isEmpty else {
                self.context.toast(L("복사할 Finder 항목이 없습니다", "No Finder items to copy"))
                return
            }
            // 경로의 한글을 NFC로 — 다른 곳에 붙여넣어도 자소분리 없음
            let text = raw.precomposedStringWithCanonicalMapping
            PasteboardWriter.copy(text, origin: .paths)
            let count = text.split(separator: "\n").count
            self.context.toast(count == 1 ? L("경로를 복사했습니다\n\(text)", "Path copied\n\(text)") : L("경로 \(count)개를 복사했습니다", "Copied \(count) paths"))
        }
    }

    /// Finder가 응답하지 않거나 자동화 권한 확인 창이 떠 있어도 PolyMac이 멈추지 않도록
    /// osascript를 백그라운드에서 실행하고, 오래 걸리면 끊는다.
    private func runAppleScript(_ source: String, completion: @escaping @MainActor (String?) -> Void) {
        let logger = context.logger
        let context = context
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            let done = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in done.signal() }
            do {
                try process.run()
            } catch {
                logger.error("osascript launch failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(nil) } }
                return
            }
            // 자동화 권한 확인 창에 답할 시간을 포함해 60초
            if done.wait(timeout: .now() + 60) == .timedOut {
                process.terminate()
                logger.error("osascript timed out")
            }
            let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errorText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let status = process.isRunning ? -1 : process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard status == 0 else {
                        logger.error("AppleScript failed: status=\(status) \(errorText, privacy: .public)")
                        if errorText.contains("-1743") {
                            context.toast(L("Finder 제어 권한이 필요합니다\n시스템 설정 › 개인정보 보호 및 보안 › 자동화", "PolyMac needs permission to control Finder\nSystem Settings › Privacy & Security › Automation"), duration: 4)
                            Permissions.openSettings(for: .automationFinder)
                        } else {
                            context.toast(L("Finder 경로를 가져오지 못했습니다", "Could not get the Finder path"))
                        }
                        completion(nil)
                        return
                    }
                    completion(output)
                }
            }
        }
    }
}

/// "여기서 터미널 열기"에 쓸 수 있는 터미널 앱.
struct TerminalApp {
    enum Launch {
        /// `open -a 앱 폴더` — 폴더에서 새 창을 연다
        case openFolder
        /// 앱 번들 안 실행 파일 + 인수 + 폴더
        case executable(String, [String])
    }

    let bundleID: String
    let name: String
    let launch: Launch

    static let defaultsKey = "finder.terminalBundleID"

    static var known: [TerminalApp] { [
        TerminalApp(bundleID: "com.apple.Terminal", name: L("터미널", "Terminal"), launch: .openFolder),
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm2", launch: .openFolder),
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty", launch: .openFolder),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp", launch: .openFolder),
        TerminalApp(bundleID: "com.github.wez.wezterm", name: "WezTerm", launch: .executable("wezterm", ["start", "--cwd"])),
        TerminalApp(bundleID: "org.alacritty", name: "Alacritty", launch: .executable("alacritty", ["--working-directory"])),
        TerminalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty", launch: .executable("kitty", ["--single-instance", "--directory"])),
    ] }

    /// 이 Mac에 설치된 것만
    static var installed: [TerminalApp] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    static var current: TerminalApp {
        let id = UserDefaults.standard.string(forKey: defaultsKey) ?? "com.apple.Terminal"
        return installed.first { $0.bundleID == id } ?? known[0]
    }

    func open(folder: String) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ModuleError(L("\(name)이(가) 설치되어 있지 않습니다", "\(name) is not installed"))
        }
        switch launch {
        case .openFolder:
            NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        case .executable(let binary, let arguments):
            let process = Process()
            process.executableURL = appURL.appendingPathComponent("Contents/MacOS/\(binary)")
            process.arguments = arguments + [folder]
            process.currentDirectoryURL = URL(fileURLWithPath: folder, isDirectory: true)
            try process.run()
        }
    }
}
