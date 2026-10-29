import AppKit
import PolyMacCore
import SwiftUI

/// 환경 설정 › Finder 도구 탭 — 터미널 열기·에디터로 열기에 쓸 앱. 메뉴의 하위 메뉴와 같은 값(UserDefaults)을 바꾼다.
/// 기능이 꺼져 있어도 미리 골라 둘 수 있다.
public struct FinderAppsPane: View {
    @State private var terminalID = TerminalApp.current.bundleID
    @State private var editor = EditorApp.current

    public init() {}

    private var editors: [EditorApp] {
        var apps = EditorApp.installedKnown
        // 직접 고른 앱도 목록에 보이게
        if !apps.contains(editor) { apps.insert(editor, at: 0) }
        return apps
    }

    public var body: some View {
        Form {
            Section {
                Picker(L("터미널 앱", "Terminal app"), selection: Binding(get: { terminalID }, set: { id in
                    terminalID = id
                    UserDefaults.standard.set(id, forKey: TerminalApp.defaultsKey)
                })) {
                    ForEach(TerminalApp.installed, id: \.bundleID) { app in
                        AppLabel(name: app.name, bundleID: app.bundleID).tag(app.bundleID)
                    }
                }
            } header: {
                Text(L("여기서 터미널 열기", "Open Terminal Here"))
            } footer: {
                Text(L("설치된 것만 보입니다. 지원: ", "Only installed apps are shown. Supported: ") + TerminalApp.known.map(\.name).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker(L("에디터 앱", "Editor app"), selection: Binding(get: { editor.bundleID }, set: { id in
                    UserDefaults.standard.set(id, forKey: EditorApp.defaultsKey)
                    editor = EditorApp.current
                })) {
                    ForEach(editors, id: \.bundleID) { app in
                        AppLabel(name: app.name, bundleID: app.bundleID).tag(app.bundleID)
                    }
                }
                HStack {
                    Spacer()
                    Button(L("다른 앱 고르기…", "Choose Another App…")) {
                        if let chosen = EditorApp.choose() { editor = chosen }
                    }
                }
            } header: {
                Text(L("에디터로 열기", "Open in Editor"))
            } footer: {
                Text(L("폴더는 에디터의 작업 공간으로 열립니다. CotEditor·텍스트 편집기처럼 폴더를 열지 못하는 앱에는 파일만 넘깁니다.",
                       "Folders open as the editor's workspace. Apps that can't open folders (CotEditor, TextEdit) get files only."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text(L("단축키는 단축키 탭에서, 우클릭 메뉴는 Finder 우클릭 › 서비스에서 씁니다.",
                       "Change shortcuts in the Shortcuts tab; the right-click items are under Finder right-click › Services."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            terminalID = TerminalApp.current.bundleID
            editor = EditorApp.current
        }
    }
}

/// 앱 아이콘 + 이름
private struct AppLabel: View {
    let name: String
    let bundleID: String

    var body: some View {
        if let url = EditorApp.appURL(bundleID) {
            Label {
                Text(name)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            }
        } else {
            Text(name)
        }
    }
}
