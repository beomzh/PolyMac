import AppKit
import PolyMacCore
import SwiftUI

/// 처음 실행할 때 한 번 뜨는 시작 안내 — 소개 → 기능 고르기 → 권한 → 마무리.
/// 메뉴 › 시작 안내…로 다시 열 수 있다. 열 때만 만들고, 닫으면 내용을 버린다.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    private static let doneKey = "onboarding.done"

    private var window: NSWindow?
    private var model: SettingsModel?

    /// 처음 실행이면 true. 이미 쓰던 사람(설정이 남아 있음)은 업데이트로 갑자기 뜨지 않게 본 것으로 친다.
    static var shouldShowAtLaunch: Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return false }
        let usedBefore = defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("module.") || $0.hasPrefix("hotkey.") || $0.hasPrefix("permission.")
        }
        if usedBefore { defaults.set(true, forKey: doneKey) }
        return !usedBefore
    }

    func show(host: SettingsHost) {
        if let window {
            model?.refresh()
            window.bringToFront()
            return
        }
        let model = SettingsModel(host: host)
        let w = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
                               styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = L("PolyMac 시작하기", "Welcome to PolyMac")
        w.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: OnboardingView(model: model) { [weak w] in w?.performClose(nil) })
        // 내용 높이에 맞춰 창이 화면 밖까지 늘어나지 않게 — 최소 크기만 따르고, 넘치는 내용은 각 단계 안에서 스크롤
        hosting.sizingOptions = [.minSize]
        w.contentViewController = hosting
        var size = NSSize(width: 680, height: 600)
        if let visible = NSScreen.main?.visibleFrame {
            size.height = min(size.height, visible.height - 40)
        }
        w.setContentSize(size)
        w.delegate = self
        w.center()
        window = w
        self.model = model
        w.bringToFront()
    }

    /// 마치기를 누르지 않고 닫아도 다시 띄우지 않는다 (메뉴에서 언제든 다시 열 수 있음)
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        model?.stopWatching()
        window?.contentViewController = nil
        window = nil
        model = nil
    }
}

private enum Step: Int, CaseIterable {
    case welcome, features, permissions, finish

    var title: String {
        switch self {
        case .welcome: return L("소개", "Welcome")
        case .features: return L("기능 고르기", "Features")
        case .permissions: return L("권한", "Permissions")
        case .finish: return L("마무리", "Finish")
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    let close: () -> Void
    @State private var step = Step.welcome

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider()
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .features: FeaturesStep(model: model)
                case .permissions: PermissionsStep(model: model)
                case .finish: FinishStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Divider()
            HStack {
                if step != .welcome {
                    Button(L("이전", "Back")) { move(-1) }
                }
                Spacer()
                if step == .finish {
                    Button(L("시작하기", "Get Started"), action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button(L("다음", "Next")) { move(1) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(minWidth: 560, minHeight: 440)
    }

    private var progress: some View {
        HStack(spacing: 16) {
            // 단계 이름을 눌러 바로 넘어간다 (다음·이전 버튼과 같은 동작)
            ForEach(Step.allCases, id: \.self) { s in
                Button { go(to: s) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.rawValue < step.rawValue ? "checkmark.circle.fill" : (s == step ? "circle.inset.filled" : "circle"))
                            .foregroundStyle(s.rawValue <= step.rawValue ? Color.accentColor : .secondary)
                        Text(s.title).font(.callout).foregroundStyle(s == step ? .primary : .secondary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("\(s.title)(으)로 이동", "Go to \(s.title)"))
            }
        }
        .padding(.vertical, 12)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        go(to: next)
    }

    private func go(to next: Step) {
        guard next != step else { return }
        model.refresh()
        step = next
    }
}

private struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            content.frame(maxWidth: .infinity)
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(L("PolyMac에 오신 것을 환영합니다", "Welcome to PolyMac")).font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                point("square.grid.2x2", L("창 분할 · 캡처 · 텍스트 추출 · 클립보드 기록 · Finder 도구 · 한글 파일명 정리 · 자동 정리 · 앱 삭제를 메뉴바 앱 하나로",
                                           "Window layout, capture, text recognition, clipboard history, Finder tools, Korean filename fix, auto-organize and an uninstaller in one menu bar app"))
                point("wifi.slash", L("인터넷에 연결하지 않습니다. 모든 처리는 이 Mac 안에서만 합니다.",
                                      "It never connects to the internet. Everything runs on this Mac."))
                point("memorychip", L("쓰지 않는 기능은 꺼 두면 메모리에서 내려갑니다.",
                                      "Features you turn off are unloaded from memory."))
                point("menubar.rectangle", L("메뉴바의 큐브 아이콘에서 모든 기능과 환경 설정을 엽니다.",
                                             "Everything lives under the cube icon in the menu bar."))
            }
            .frame(maxWidth: 480, alignment: .leading)
        }
        .padding(24)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 22)
        }
    }
}

private struct FeaturesStep: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(model.descriptors, id: \.id) { d in
                    Toggle(isOn: Binding(get: { model.active.contains(d.id) }, set: { model.setEnabled(d.id, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.displayName)
                            Text(d.summary).font(.caption).foregroundStyle(.secondary)
                            let needs = d.permissions.filter { Permission.shown.contains($0) }
                            if !needs.isEmpty {
                                Text(L("필요한 권한: ", "Needs: ") + needs.map(\.title).joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text(L("쓸 기능만 켜 두세요", "Keep on only what you use"))
            } footer: {
                Text(L("나중에 환경 설정 › 기능에서 언제든 바꿀 수 있습니다.", "You can change this any time in Settings › Features."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsStep: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("켜 둔 기능에 필요한 권한만 허용하면 됩니다. \"허용하기…\"를 누르면 시스템 설정이 열리고, 거기서 PolyMac을 켜면 이 화면에 바로 반영됩니다.",
                   "Allow only what your enabled features need. \"Allow…\" opens System Settings; turn PolyMac on there and this screen updates by itself."))
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 14)
            PermissionsPane(model: model, compact: true)
        }
    }
}

private struct FinishStep: View {
    @ObservedObject var model: SettingsModel

    /// 켜진 기능마다 첫 단축키 하나씩
    private var shortcuts: [HotkeyCenter.Registration] {
        var seen = Set<String>()
        return HotkeyCenter.shared.registrations.filter { r in
            guard r.combo != nil, model.active.contains(r.owner), !seen.contains(r.owner) else { return false }
            seen.insert(r.owner)
            return true
        }
    }

    var body: some View {
        Form {
            Section(L("자주 쓰는 단축키", "Handy shortcuts")) {
                if shortcuts.isEmpty {
                    Text(L("켜진 기능에 단축키가 없습니다.", "No enabled feature has a shortcut.")).foregroundStyle(.secondary)
                }
                ForEach(shortcuts) { r in
                    LabeledContent(r.name) {
                        Text(r.combo?.display ?? "").font(.body.monospaced())
                    }
                }
            }
            Section {
                Toggle(L("로그인 시 자동 실행", "Open at login"), isOn: Binding(get: { model.loginItem }, set: { model.setLoginItem($0) }))
            } footer: {
                Text(L("단축키는 환경 설정 › 단축키에서 바꾸거나 지울 수 있습니다. 이 안내는 메뉴 › 시작 안내…에서 다시 볼 수 있습니다.",
                       "Change or clear shortcuts in Settings › Shortcuts. Reopen this guide from the menu › Welcome Guide…"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}
