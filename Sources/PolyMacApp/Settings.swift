import AppKit
import PolyMacCore
import ServiceManagement
import SwiftUI

/// 환경 설정 창이 앱에 부탁하는 일. AppDelegate가 맡는다.
@MainActor
protocol SettingsHost: AnyObject {
    var descriptors: [ModuleDescriptor] { get }
    func isActive(_ id: String) -> Bool
    /// 켜기에 실패하면 이유를 돌려준다
    func setEnabled(_ id: String, _ on: Bool) -> String?
    /// 언어를 바꾼 뒤 메뉴·단축키 이름·창 문구를 새 언어로 다시 만든다
    func languageChanged()
}

/// 환경 설정 창 — 기능 · 언어 · 단축키 · 권한. 열 때만 만들고, 닫으면 내용을 버린다.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private var model: SettingsModel?

    enum Tab: String, CaseIterable, Identifiable {
        case features, language, notifications, shortcuts, permissions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .features: return L("기능", "Features")
            case .language: return L("언어", "Language")
            case .notifications: return L("알림", "Notifications")
            case .shortcuts: return L("단축키", "Shortcuts")
            case .permissions: return L("권한", "Permissions")
            }
        }
        var symbol: String {
            switch self {
            case .features: return "square.grid.2x2"
            case .language: return "globe"
            case .notifications: return "text.bubble"
            case .shortcuts: return "command"
            case .permissions: return "lock.shield"
            }
        }
    }

    func show(host: SettingsHost, tab: Tab? = nil) {
        if let window, let model {
            if let tab { model.tab = tab }
            model.refresh()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(host: host)
        if let tab { model.tab = tab }
        let w = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = L("PolyMac 환경 설정", "PolyMac Settings")
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        w.delegate = self
        w.center()
        window = w
        self.model = model
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    /// 언어가 바뀌면 창 제목도 새 언어로
    func retitle() {
        window?.title = L("PolyMac 환경 설정", "PolyMac Settings")
    }

    func windowWillClose(_ notification: Notification) {
        model?.shortcuts.stopRecording()
        model?.stopWatching()
        window?.contentViewController = nil
        window = nil
        model = nil
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var tab: SettingsWindow.Tab = .features
    @Published private(set) var active: Set<String> = []
    @Published private(set) var language = L10n.language
    @Published private(set) var loginItem = SMAppService.mainApp.status == .enabled
    @Published private(set) var granted: [Permission: Bool] = [:]
    @Published var message: String?
    let shortcuts: ShortcutSettingsModel

    private weak var host: SettingsHost?
    private var timer: Timer?

    init(host: SettingsHost) {
        self.host = host
        shortcuts = ShortcutSettingsModel { [weak host] id in
            host?.descriptors.first { $0.id == id }?.displayName ?? id
        }
        refresh()
        // 권한은 시스템 설정에서 바뀌므로 창이 떠 있는 동안만 가끔 다시 확인
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    var descriptors: [ModuleDescriptor] { host?.descriptors ?? [] }

    func refresh() {
        active = Set(descriptors.map(\.id).filter { host?.isActive($0) == true })
        loginItem = SMAppService.mainApp.status == .enabled
        refreshPermissions()
        shortcuts.reload()
    }

    private func refreshPermissions() {
        let now: [Permission: Bool] = [.accessibility: Permissions.accessibility, .screenRecording: Permissions.screenRecording]
        if now != granted { granted = now }
    }

    // MARK: 기능

    func setEnabled(_ id: String, _ on: Bool) {
        message = host?.setEnabled(id, on)
        refresh()
    }

    // MARK: 언어

    func setLanguage(_ language: AppLanguage) {
        guard language != L10n.language else { return }
        L10n.language = language
        self.language = language
        host?.languageChanged()
        SettingsWindow.shared.retitle()
        refresh()
        objectWillChange.send() // 모든 문구를 새 언어로 다시 그린다
    }

    // MARK: 일반

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = L("로그인 항목 변경 실패: ", "Could not change the login item: ") + error.localizedDescription
        }
        loginItem = SMAppService.mainApp.status == .enabled
    }

    // MARK: 권한

    /// 이 권한을 쓰는 켜진 기능의 이름
    func users(of permission: Permission) -> [String] {
        descriptors.filter { $0.permissions.contains(permission) }.map(\.displayName)
    }

    func request(_ permission: Permission) {
        switch permission {
        case .accessibility where !Permissions.accessibility: Permissions.requestAccessibility()
        case .screenRecording where !Permissions.screenRecording: Permissions.requestScreenRecording()
        default: break
        }
        Permissions.openSettings(for: permission)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        // 설정 창의 사이드바는 접지 않는다 — 접기 버튼이 있으면 접었을 때 툴바 오른쪽으로 옮겨 가 헷갈린다
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsWindow.Tab.allCases, selection: Binding(get: { model.tab }, set: { if let t = $0 { model.tab = t } })) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                switch model.tab {
                case .features: FeaturesPane(model: model)
                case .language: LanguagePane(model: model)
                case .notifications: NotificationsPane()
                case .shortcuts: ShortcutSettingsView(model: model.shortcuts)
                case .permissions: PermissionsPane(model: model)
                }
                if let message = model.message {
                    Divider()
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

private struct FeaturesPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(model.descriptors, id: \.id) { d in
                    Toggle(isOn: Binding(get: { model.active.contains(d.id) }, set: { model.setEnabled(d.id, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.displayName)
                            Text(d.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L("기능 켜기 / 끄기", "Turn features on or off"))
            } footer: {
                Text(L("끈 기능은 메모리에서 내려가고 단축키도 해제됩니다.", "A disabled feature is unloaded from memory and its shortcuts are released."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("앱", "App")) {
                Toggle(L("로그인 시 자동 실행", "Open at login"), isOn: Binding(get: { model.loginItem }, set: { model.setLoginItem($0) }))
                LabeledContent(L("데이터 폴더", "Data folder")) {
                    Button(L("Finder에서 열기", "Show in Finder")) { NSWorkspace.shared.open(AppPaths.dataDirectory) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LanguagePane: View {
    @ObservedObject var model: SettingsModel

    private func title(_ language: AppLanguage) -> String {
        switch language {
        case .system: return L("시스템 설정 따르기", "Use system language")
        case .ko: return "한국어"
        case .en: return "English"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker(L("화면 언어", "Display language"), selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text(title($0)).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(L("바로 바뀝니다. \"시스템 설정 따르기\"는 macOS 첫 번째 언어가 한국어면 한국어, 아니면 영어입니다.",
                       "Applies immediately. \"Use system language\" picks Korean when it is your first macOS language, otherwise English."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 안내 토스트의 글자색·배경색·글자 크기·알림창 크기. 바꾸면 바로 저장하고 미리보기를 띄운다.
private struct NotificationsPane: View {
    @State private var style = ToastStyle.current

    private var sample: String {
        L("캡처를 클립보드에 복사했습니다\n알림 문구는 이렇게 보입니다", "Copied the capture to the clipboard\nNotifications look like this")
    }

    /// nil(시스템 색)과 직접 고른 색을 오가는 바인딩
    private func colorBinding(_ keyPath: WritableKeyPath<ToastStyle, String?>, fallback: NSColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: style[keyPath: keyPath].flatMap(ToastStyle.color(hex:)) ?? fallback) },
            set: { style[keyPath: keyPath] = ToastStyle.hex(NSColor($0)) }
        )
    }

    private func systemBinding(_ keyPath: WritableKeyPath<ToastStyle, String?>, fallback: NSColor) -> Binding<Bool> {
        Binding(
            get: { style[keyPath: keyPath] == nil },
            set: { useSystem in
                var resolved = fallback
                NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = fallback.usingColorSpace(.sRGB) ?? fallback }
                style[keyPath: keyPath] = useSystem ? nil : ToastStyle.hex(resolved)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(L("글자색: 시스템 설정 따르기", "Text color: follow system"), isOn: systemBinding(\.textColor, fallback: .labelColor))
                if style.textColor != nil {
                    ColorPicker(L("글자색", "Text color"), selection: colorBinding(\.textColor, fallback: .labelColor), supportsOpacity: false)
                }
                Toggle(L("배경색: 시스템 설정 따르기", "Background: follow system"), isOn: systemBinding(\.backgroundColor, fallback: .windowBackgroundColor))
                if style.backgroundColor != nil {
                    ColorPicker(L("배경색", "Background color"), selection: colorBinding(\.backgroundColor, fallback: .windowBackgroundColor), supportsOpacity: true)
                }
            } header: {
                Text(L("색", "Colors"))
            } footer: {
                Text(L("\"시스템 설정 따르기\"는 라이트·다크 모드에 맞춰 바뀝니다. 직접 고른 색은 모드와 관계없이 그대로입니다.",
                       "\"Follow system\" adapts to light and dark mode. A color you pick stays the same in both."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("크기", "Size")) {
                slider(L("글자 크기", "Font size"), value: $style.fontSize, range: ToastStyle.fontSizes, step: 1, unit: "pt")
                slider(L("알림창 최대 너비", "Maximum width"), value: $style.maxWidth, range: ToastStyle.maxWidths, step: 20, unit: "pt")
                slider(L("안쪽 여백", "Padding"), value: $style.padding, range: ToastStyle.paddings, step: 1, unit: "pt")
            }
            Section {
                HStack {
                    Button(L("미리보기", "Preview")) { Toast.show(sample, duration: 3, style: style) }
                    Spacer()
                    Button(L("기본값으로", "Restore Defaults")) { style = ToastStyle() }
                        .disabled(style == ToastStyle())
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: style) { _, new in
            new.save()
            Toast.show(sample, duration: 2, style: new)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step).frame(minWidth: 180)
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}

private struct PermissionsPane: View {
    @ObservedObject var model: SettingsModel

    private struct Row: Identifiable {
        let permission: Permission
        let title: String
        let detail: String
        /// nil = macOS가 처음 쓸 때 직접 물어서 미리 확인할 수 없음
        let granted: Bool?
        var id: String { permission.rawValue }
    }

    private var rows: [Row] {
        [
            Row(permission: .accessibility, title: L("손쉬운 사용", "Accessibility"),
                detail: L("창 배치, Finder ⌘X, 클립보드 자동 붙여넣기", "Window layout, Finder ⌘X, clipboard auto-paste"),
                granted: model.granted[.accessibility]),
            Row(permission: .screenRecording, title: L("화면 및 시스템 오디오 녹음", "Screen & System Audio Recording"),
                detail: L("캡처, 텍스트 추출(OCR)", "Capture, text recognition (OCR)"),
                granted: model.granted[.screenRecording]),
            Row(permission: .automationFinder, title: L("자동화 › Finder", "Automation › Finder"),
                detail: L("터미널 열기, 경로 복사, 앱 삭제(휴지통으로 옮기기)", "Open Terminal, copy path, uninstall (move to Trash)"),
                granted: nil),
            Row(permission: .filesAndFolders, title: L("파일 및 폴더", "Files & Folders"),
                detail: L("자소분리 정리, 다운로드 자동 정리", "Korean filename fix, Downloads auto-organize"),
                granted: nil),
        ]
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        status(row.granted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            let users = model.users(of: row.permission)
                            if !users.isEmpty {
                                Text(L("쓰는 기능: ", "Used by: ") + users.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button(row.granted == false ? L("허용하기…", "Allow…") : L("설정 열기", "Open Settings")) {
                            model.request(row.permission)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text(L("PolyMac은 네트워크를 쓰지 않고 모든 처리를 이 Mac 안에서 합니다. 자동화·파일 권한은 처음 쓸 때 macOS가 직접 묻습니다.",
                       "PolyMac never uses the network; everything runs on this Mac. macOS asks for Automation and Files & Folders the first time they are needed."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func status(_ granted: Bool?) -> some View {
        switch granted {
        case true?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("허용됨", "Allowed"))
        case false?:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(L("허용 필요", "Needs permission"))
        case nil:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(L("처음 쓸 때 macOS가 묻습니다", "macOS asks on first use"))
        }
    }
}
