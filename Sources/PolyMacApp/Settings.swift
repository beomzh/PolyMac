import AppKit
import Combine
import FinderModule
import NormalizeModule
import OrganizeModule
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
        case features, language, notifications, finder, normalize, organize, shortcuts, permissions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .features: return L("기능", "Features")
            case .language: return L("언어", "Language")
            case .notifications: return L("알림", "Notifications")
            case .finder: return L("Finder 도구", "Finder Tools")
            case .normalize: return L("한글 파일명", "Korean Filenames")
            case .organize: return L("자동 정리", "Auto-Organize")
            case .shortcuts: return L("단축키", "Shortcuts")
            case .permissions: return L("권한", "Permissions")
            }
        }
        var symbol: String {
            switch self {
            case .features: return "square.grid.2x2"
            case .language: return "globe"
            case .notifications: return "text.bubble"
            case .finder: return "macwindow.on.rectangle"
            case .normalize: return "folder.badge.gearshape"
            case .organize: return "tray.full"
            case .shortcuts: return "command"
            case .permissions: return "lock.shield"
            }
        }
    }

    func show(host: SettingsHost, tab: Tab? = nil) {
        if let window, let model {
            if let tab { model.tab = tab }
            model.refresh()
            window.bringToFront()
            return
        }
        let model = SettingsModel(host: host)
        if let tab { model.tab = tab }
        let w = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = L("PolyMac 환경 설정", "PolyMac Settings")
        w.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // 내용 크기에 맞춰 창이 저절로 줄었다 늘었다 하지 않게 — 최소 크기만 따른다 (크기는 defaultSize)
        hosting.sizingOptions = [.minSize]
        w.contentViewController = hosting
        w.setContentSize(Self.defaultSize(on: NSScreen.main))
        w.delegate = self
        w.center()
        window = w
        self.model = model
        w.bringToFront()
    }

    /// 모든 탭에 같은 크기 — 가장 넓은 자동 정리(규칙 목록 + 편집)에 맞춰, 탭을 바꿔도 창이 커졌다 작아졌다 하지 않게.
    /// 작은 화면에서는 화면 안에 들어오게 줄인다.
    private static func defaultSize(on screen: NSScreen?) -> NSSize {
        var size = NSSize(width: 1000, height: 680)
        if let visible = screen?.visibleFrame {
            size.width = min(size.width, visible.width - 40)
            size.height = min(size.height, visible.height - 40)
        }
        return size
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
    @Published private(set) var states: [Permission: PermissionState] = [:]
    /// 켜진 기능이 쓰는데, 예전에는 허용됐다가 지금은 꺼진 권한 (서명 변경 등)
    @Published private(set) var lost: [Permission] = []
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

    private var checkingAutomation = false

    private func refreshPermissions() {
        var now = PermissionState.current()
        now[.automationFinder] = states[.automationFinder] ?? .unknown
        if now != states { states = now }
        PermissionMemory.note(now)
        let missing = PermissionMemory.lost(now, needed: neededPermissions)
        if missing != lost { lost = missing }
        refreshAutomation()
    }

    /// Finder에 물어봐야 해서 메인 스레드 밖에서
    private func refreshAutomation(ask: Bool = false) {
        guard ask || !checkingAutomation else { return } // "허용하기"는 확인 중이어도 바로 묻는다
        checkingAutomation = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                ask ? Permissions.requestAutomationFinder() : Permissions.automationFinder()
            }.value
            self?.applyAutomation(result, asked: ask)
        }
    }

    private func applyAutomation(_ result: AutomationState, asked: Bool) {
        checkingAutomation = false
        let state = PermissionState(result)
        let previous = states[.automationFinder]
        // Finder가 꺼져 있거나 잠깐 응답하지 않으면(unknown) 마지막으로 확인한 값을 그대로 둔다
        let keep = state == .unknown && previous != nil && previous != .unknown
        if !keep, previous != state { states[.automationFinder] = state }
        if asked, result == .denied { Permissions.openSettings(for: .automationFinder) }
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
        descriptors.filter { active.contains($0.id) && $0.permissions.contains(permission) }.map(\.displayName)
    }

    /// 켜진 기능이 쓰는 권한
    var neededPermissions: Set<Permission> {
        Set(descriptors.filter { active.contains($0.id) }.flatMap(\.permissions))
    }

    func request(_ permission: Permission) {
        switch permission {
        case .accessibility where !Permissions.accessibility: Permissions.requestAccessibility()
        case .screenRecording where !Permissions.screenRecording: Permissions.requestScreenRecording()
        case .automationFinder where states[.automationFinder] == .notAsked:
            refreshAutomation(ask: true) // macOS가 허용 창을 띄운다 — 시스템 설정은 열지 않는다
            return
        default: break
        }
        Permissions.openSettings(for: permission)
    }

    func relaunch() {
        Permissions.relaunch()
    }

    /// PolyMac 권한 기록을 지우고 다시 실행 — 다시 열리면 권한 탭이 열린다
    func resetPermissionRecords() {
        let ok = Permissions.resetRecords()
        PermissionMemory.forget()
        guard ok else {
            message = L("권한 기록을 지우지 못했습니다. README의 \"권한 초기화\" 명령을 터미널에서 실행해 보세요.",
                        "Could not reset the permission records. Try the \"reset permissions\" commands in the README.")
            return
        }
        UserDefaults.standard.set(true, forKey: PermissionMemory.openAfterLaunchKey)
        Permissions.relaunch()
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
                case .finder: FinderAppsPane()
                case .normalize: NormalizePane()
                case .organize: OrganizeRulesPane()
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

/// 안내 토스트 켜기·위치·표시 시간·글자색·배경색·글자 크기·알림창 크기. 바꾸면 바로 저장하고 미리보기를 띄운다.
private struct NotificationsPane: View {
    @State private var style = ToastStyle.current

    private var sample: String {
        L("텍스트를 클립보드에 복사했습니다", "Text copied to the clipboard")
    }

    /// 미리보기에서 안내 문구와 내용 상자가 어떻게 나뉘는지 함께 보여준다
    private var sampleContent: String {
        L("맥에서 만든 한글 파일명이 윈도우에서 깨지는 문제…", "Recognized text appears here, separate from the notice…")
    }

    var body: some View {
        Form {
            Section {
                Toggle(L("알림 보이기", "Show notifications"), isOn: $style.isEnabled)
                Picker(L("위치", "Position"), selection: $style.position) {
                    ForEach(ToastPosition.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
                }
                .disabled(!style.isEnabled)
                LabeledContent(L("표시 시간", "Display time")) {
                    HStack {
                        Slider(value: $style.seconds, in: ToastStyle.secondsRange, step: 0.5).frame(minWidth: 180)
                        Text(L("\(style.seconds.formatted())초", "\(style.seconds.formatted()) s")).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!style.isEnabled)
            } header: {
                Text(L("알림", "Notifications"))
            } footer: {
                Text(style.isEnabled
                     ? L("실패·권한 안내처럼 원래 더 오래 뜨는 알림은 같은 비율로 길어집니다.",
                         "Messages that normally stay longer (errors, permission notices) scale by the same ratio.")
                     : L("모든 안내 알림이 꺼집니다 — 권한이 필요하거나 동작이 실패해도 알림이 뜨지 않습니다. 미리보기는 그대로 볼 수 있습니다.",
                         "All notifications are hidden, including permission and error notices. Preview still works."))
                    .font(.caption).foregroundStyle(style.isEnabled ? Color.secondary : Color.orange)
            }
            Section {
                ColorChoiceRow(title: L("글자색", "Text color"), hex: $style.textColor, fallback: .labelColor,
                               swatches: ["#FFFFFF", "#000000", "#8E8E93", "#FFD60A", "#0A84FF", "#FF453A"], opacity: false)
                ColorChoiceRow(title: L("배경색", "Background"), hex: $style.backgroundColor, fallback: .windowBackgroundColor,
                               swatches: ["#1E1E1EE6", "#FFFFFFF2", "#0A84FFE6", "#30D158E6", "#FF9F0AE6", "#FF453AE6"], opacity: true)
            } header: {
                Text(L("색", "Colors"))
            } footer: {
                Text(L("\"시스템\"은 라이트·다크 모드에 맞춰 바뀝니다. 견본이나 직접 고른 색은 모드와 관계없이 그대로입니다.",
                       "\"System\" adapts to light and dark mode. A swatch or a color you pick stays the same in both."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("크기", "Size")) {
                slider(L("글자 크기", "Font size"), value: $style.fontSize, range: ToastStyle.fontSizes, step: 1, unit: "pt")
                slider(L("알림창 최대 너비", "Maximum width"), value: $style.maxWidth, range: ToastStyle.maxWidths, step: 20, unit: "pt")
                slider(L("안쪽 여백", "Padding"), value: $style.padding, range: ToastStyle.paddings, step: 1, unit: "pt")
            }
            Section {
                HStack {
                    Button(L("미리보기", "Preview")) { Toast.show(sample, content: sampleContent, duration: style.seconds, style: style) }
                    Spacer()
                    Button(L("기본값으로", "Restore Defaults")) { style = ToastStyle() }
                        .disabled(style == ToastStyle())
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: style) { _, new in
            new.save()
            Toast.show(sample, content: sampleContent, duration: new.seconds, style: new)
        }
    }

    private static func title(_ position: ToastPosition) -> String {
        switch position {
        case .bottomCenter: return L("아래 가운데 (기본)", "Bottom center (default)")
        case .bottomLeft: return L("왼쪽 아래", "Bottom left")
        case .bottomRight: return L("오른쪽 아래", "Bottom right")
        case .center: return L("화면 가운데", "Center")
        case .topCenter: return L("위 가운데", "Top center")
        case .topLeft: return L("왼쪽 위", "Top left")
        case .topRight: return L("오른쪽 위", "Top right")
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

/// 색 한 줄: [시스템] [견본…] [직접 고르기]. 고른 칸에 테두리를 두른다.
private struct ColorChoiceRow: View {
    let title: String
    @Binding var hex: String?
    /// "시스템"일 때 쓰는 동적 색 (칸 안에 현재 모드로 그려 보여준다)
    let fallback: NSColor
    let swatches: [String]
    let opacity: Bool

    private var isCustom: Bool { hex != nil && !swatches.contains(hex!) }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                chip(Color(nsColor: fallback), selected: hex == nil, help: L("시스템 설정 따르기", "Follow system")) { hex = nil }
                    .overlay(Text("A").font(.caption2.bold()).foregroundStyle(.secondary).allowsHitTesting(false))
                Divider().frame(height: 18)
                ForEach(swatches, id: \.self) { value in
                    if let color = ToastStyle.color(hex: value) {
                        chip(Color(nsColor: color), selected: hex == value, help: value) { hex = value }
                    }
                }
                Divider().frame(height: 18)
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: hex.flatMap(ToastStyle.color(hex:)) ?? fallback) },
                    set: { hex = ToastStyle.hex(NSColor($0)) }
                ), supportsOpacity: opacity)
                .labelsHidden()
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: isCustom ? 2 : 0).padding(-3))
                .help(L("직접 고르기", "Choose a color"))
                Text(L("직접 고르기", "Custom")).font(.caption).foregroundStyle(isCustom ? .primary : .secondary)
            }
        }
    }

    private func chip(_ color: Color, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.25), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor, lineWidth: selected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// 한글 자소분리 자동 정리가 감시할 폴더. 바꾸면 바로 저장하고 모듈이 감시를 다시 시작한다.
private struct NormalizePane: View {
    @State private var folders = NormalizeFolders.load()
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                ForEach($folders, id: \.path) { $folder in
                    HStack {
                        Toggle("", isOn: $folder.isEnabled).labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.path).lineLimit(1).truncationMode(.middle)
                            if let problem = NormalizeFolders.problem(with: folder.expandedPath) {
                                Text(problem).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: folder.expandedPath)) } label: { Image(systemName: "folder") }
                            .buttonStyle(.borderless)
                            .help(L("Finder에서 열기", "Show in Finder"))
                        Button { folders.removeAll { $0.path == folder.path } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help(L("목록에서 빼기", "Remove from list"))
                    }
                }
                if folders.isEmpty {
                    Text(L("감시하는 폴더가 없습니다", "No folders are watched")).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("폴더 추가…", "Add Folder…")) { add() }
                    Spacer()
                    Button(L("기본값으로", "Restore Defaults")) {
                        folders = NormalizeFolders.defaults.map { NormalizeFolders.Folder(path: $0) }
                    }
                    .disabled(folders == NormalizeFolders.defaults.map { NormalizeFolders.Folder(path: $0) })
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text(L("자소분리를 검사할 폴더", "Folders to check for decomposed names"))
            } footer: {
                Text(L("폴더 바로 아래의 파일·폴더 이름만 고칩니다(하위 폴더는 우클릭 › 한글 파일명 정리). 홈 폴더 안의 폴더만 지정할 수 있고, ~/Library와 iCloud 동기화 폴더는 건드리지 않습니다. 기능이 꺼져 있으면 저장만 됩니다.",
                       "Only names directly inside each folder are fixed (use right-click › Fix Korean Filenames for subfolders). Only folders inside your home folder are allowed; ~/Library and iCloud-synced folders are never touched. If the feature is off, the list is only saved."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: folders) { _, new in NormalizeFolders.save(new) }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.prompt = L("추가", "Add")
        guard panel.runModal() == .OK else { return }
        var rejected: [String] = []
        for url in panel.urls {
            if let problem = NormalizeFolders.problem(with: url.path) {
                rejected.append("\(url.lastPathComponent): \(problem)")
                continue
            }
            let path = (url.path as NSString).abbreviatingWithTildeInPath
            if !folders.contains(where: { $0.path == path }) { folders.append(NormalizeFolders.Folder(path: path)) }
        }
        message = rejected.isEmpty ? nil : rejected.joined(separator: "\n")
    }
}

/// 권한 탭 (시작 안내의 권한 단계에서도 쓴다)
struct PermissionsPane: View {
    @ObservedObject var model: SettingsModel
    /// 시작 안내에서는 문제 해결 칸을 줄인다
    var compact = false
    @State private var confirmingReset = false

    var body: some View {
        Form {
            if !model.lost.isEmpty {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("예전에 허용했던 권한이 지금은 꺼져 있습니다: ", "Permissions you allowed before are now off: ")
                                 + model.lost.map(\.title).joined(separator: ", "))
                            Text(L("PolyMac을 새로 받아 설치했다면 서명이 바뀌어, 시스템 설정에는 켜져 보여도 동작하지 않을 수 있습니다. 아래 \"권한 기록 지우기\"로 정리한 뒤 다시 허용하세요.",
                                   "If you installed a new copy of PolyMac its signature may differ, so System Settings can show it as on while it does not work. Use \"Reset permission records\" below, then allow again."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                ForEach(Permission.shown, id: \.self) { permission in
                    row(permission)
                }
            } footer: {
                Text(L("PolyMac은 네트워크를 쓰지 않고 모든 처리를 이 Mac 안에서 합니다. 필요한 권한만 허용하면 되고, 허용하지 않은 권한을 쓰는 기능만 동작하지 않습니다.",
                       "PolyMac never uses the network; everything runs on this Mac. Allow only what you need — features whose permission is missing simply stay inactive."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("문제 해결", "Troubleshooting")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("시스템 설정에는 켜져 있는데 동작하지 않나요?", "On in System Settings but not working?"))
                    if !compact {
                        Text(L("PolyMac의 손쉬운 사용·화면 녹음·자동화 기록만 지우고 PolyMac을 다시 실행합니다. 다른 앱의 권한은 그대로입니다. 다시 열리면 이 화면에서 다시 허용하세요.",
                               "Clears only PolyMac's Accessibility, Screen Recording and Automation records, then restarts PolyMac. Other apps are not affected. Allow again on this screen when it reopens."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(L("권한 기록 지우기…", "Reset permission records…")) { confirmingReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("PolyMac 권한 기록을 지울까요?", "Reset PolyMac's permission records?"), isPresented: $confirmingReset) {
            Button(L("지우고 다시 실행", "Reset and Restart"), role: .destructive) { model.resetPermissionRecords() }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("손쉬운 사용·화면 녹음·자동화를 다시 허용해야 합니다.", "You will need to allow Accessibility, Screen Recording and Automation again."))
        }
    }

    private func row(_ permission: Permission) -> some View {
        let state = model.states[permission]
        let users = model.users(of: permission)
        return HStack(alignment: .top, spacing: 10) {
            PermissionStatusIcon(state: state)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.detail).font(.caption).foregroundStyle(.secondary)
                Text(users.isEmpty ? L("켜진 기능 중 쓰는 것이 없습니다", "No enabled feature uses this")
                                   : L("쓰는 기능: ", "Used by: ") + users.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                switch state {
                case .missing?, .notAsked?:
                    Button(L("허용하기…", "Allow…")) { model.request(permission) }
                default:
                    Button(L("설정 열기", "Open Settings")) { model.request(permission) }
                }
                // 화면 녹음은 허용해도 다시 실행하기 전까지 꺼진 것으로 보인다
                if permission == .screenRecording, state == .missing {
                    Button(L("허용했다면 다시 실행", "Restart if allowed")) { model.relaunch() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(users.isEmpty && state != .granted ? 0.6 : 1)
    }
}
