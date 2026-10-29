import AppKit
import PolyMacCore

/// "에디터로 열기"에 쓸 앱. 알려진 에디터 중 설치된 것, 또는 사용자가 직접 고른 앱.
struct EditorApp: Equatable {
    let bundleID: String
    let name: String
    /// 폴더를 넘기면 작업 공간(프로젝트)으로 연다. false면 파일만 넘긴다 (텍스트 편집기 등).
    let opensFolders: Bool

    static let defaultsKey = "finder.editorBundleID"

    /// 처음 쓸 때 이 순서로 설치된 첫 앱을 고른다 — 텍스트 편집기는 늘 있어 마지막
    static let known: [EditorApp] = [
        EditorApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", opensFolders: true),
        EditorApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", opensFolders: true),
        EditorApp(bundleID: "dev.zed.Zed", name: "Zed", opensFolders: true),
        EditorApp(bundleID: "com.sublimetext.4", name: "Sublime Text", opensFolders: true),
        EditorApp(bundleID: "com.panic.Nova", name: "Nova", opensFolders: true),
        EditorApp(bundleID: "com.barebones.bbedit", name: "BBEdit", opensFolders: true),
        EditorApp(bundleID: "com.coteditor.CotEditor", name: "CotEditor", opensFolders: false),
        EditorApp(bundleID: "com.apple.TextEdit", name: L("텍스트 편집기", "TextEdit"), opensFolders: false),
    ]

    /// 저장된 앱 → 없거나 지워졌으면 설치된 알려진 에디터 중 첫째. 알려지지 않은 앱도 설치돼 있으면 그대로 쓴다.
    static func resolve(saved: String?, isInstalled: (String) -> Bool, name: (String) -> String?) -> EditorApp {
        if let saved, isInstalled(saved) {
            if let app = known.first(where: { $0.bundleID == saved }) { return app }
            return EditorApp(bundleID: saved, name: name(saved) ?? saved, opensFolders: true)
        }
        return known.first { isInstalled($0.bundleID) } ?? known[known.count - 1]
    }

    /// 넘길 항목과 이 앱이 못 여는 폴더
    func split(_ urls: [URL], isFolder: (URL) -> Bool) -> (open: [URL], skipped: [URL]) {
        guard !opensFolders else { return (urls, []) }
        return (urls.filter { !isFolder($0) }, urls.filter(isFolder))
    }

    // MARK: - 이 Mac에서

    static var installedKnown: [EditorApp] {
        known.filter { appURL($0.bundleID) != nil }
    }

    static var current: EditorApp {
        resolve(saved: UserDefaults.standard.string(forKey: defaultsKey),
                isInstalled: { appURL($0) != nil },
                name: { id in appURL(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } })
    }

    static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// 사용자가 응용 프로그램 폴더에서 직접 고른다. 번들 ID가 없는 앱은 받지 않는다.
    @MainActor
    static func choose() -> EditorApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = L("고르기", "Choose")
        panel.message = L("Finder 항목을 열 앱을 고르세요", "Choose the app that opens Finder items")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        UserDefaults.standard.set(id, forKey: defaultsKey)
        return current
    }

    @MainActor
    func open(_ urls: [URL]) throws {
        guard let appURL = Self.appURL(bundleID) else {
            throw ModuleError(L("\(name)이(가) 설치되어 있지 않습니다", "\(name) is not installed"))
        }
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
