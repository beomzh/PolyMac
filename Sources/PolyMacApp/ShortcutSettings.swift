import AppKit
import PolyMacCore
import SwiftUI

/// 단축키 설정 창. 열 때만 만들어지고, 닫아도 다음에 다시 쓰려고 창 하나만 유지한다.
@MainActor
final class ShortcutSettingsWindow {
    static let shared = ShortcutSettingsWindow()
    private var window: NSWindow?

    func show(moduleNames: [String: String]) {
        let model = ShortcutSettingsModel(moduleNames: moduleNames)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "PolyMac 단축키"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: ShortcutSettingsView(model: model))
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ShortcutSettingsModel: ObservableObject {
    struct Group: Identifiable {
        let id: String
        let title: String
        let rows: [HotkeyCenter.Registration]
    }

    @Published private(set) var groups: [Group] = []
    @Published private(set) var recordingKey: String?
    @Published var message: String?

    private let moduleNames: [String: String]
    private var monitor: Any?

    init(moduleNames: [String: String]) {
        self.moduleNames = moduleNames
        reload()
    }

    func reload() {
        let all = HotkeyCenter.shared.registrations
        var owners: [String] = []
        for r in all where !owners.contains(r.owner) { owners.append(r.owner) }
        groups = owners.map { owner in
            Group(id: owner, title: moduleNames[owner] ?? owner, rows: all.filter { $0.owner == owner })
        }
    }

    func startRecording(_ key: String) {
        stopRecording()
        message = nil
        recordingKey = key
        // 등록된 전역 단축키가 키 입력을 먼저 가져가지 않게 녹화 동안 잠시 해제
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recordingKey != nil {
            recordingKey = nil
            HotkeyCenter.shared.resume()
        }
        reload()
    }

    func resetToDefault(_ key: String) {
        stopRecording()
        HotkeyCenter.shared.resetToDefault(key)
        message = nil
        reload()
    }

    func resetAll() {
        stopRecording()
        HotkeyCenter.shared.resetAll()
        message = "모든 단축키를 기본값으로 되돌렸습니다"
        reload()
    }

    private func handle(_ event: NSEvent) {
        guard let key = recordingKey else { return }
        switch Int(event.keyCode) {
        case 53: // Esc — 취소
            stopRecording()
            return
        case 51, 117: // ⌫ ⌦ — 사용 안 함 (수식키 없이 눌렀을 때만)
            if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                HotkeyCenter.shared.setCombo(nil, for: key)
                message = nil
                stopRecording()
                return
            }
        default:
            break
        }
        let combo = KeyCombo(event: event)
        guard combo.isUsableAsGlobalHotkey else {
            message = "⌘ · ⌃ · ⌥ 중 하나 이상과 함께 눌러 주세요 (F키는 단독 가능)"
            return
        }
        if let other = HotkeyCenter.shared.conflict(for: combo, excluding: key) {
            message = "\(combo.display)은(는) '\(other.name)'에서 이미 쓰고 있습니다"
            return
        }
        HotkeyCenter.shared.setCombo(combo, for: key)
        message = nil
        stopRecording()
        if let row = HotkeyCenter.shared.registrations.first(where: { $0.key == key }), !row.isRegistered {
            message = "\(combo.display)은(는) 다른 앱이 이미 쓰고 있어 동작하지 않을 수 있습니다"
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("바꿀 단축키를 클릭한 뒤 새 조합을 누르세요.  Esc 취소 · ⌫ 사용 안 함")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(model.groups) { group in
                    Section(group.title) {
                        ForEach(group.rows) { row in
                            ShortcutRow(row: row, isRecording: model.recordingKey == row.key,
                                        record: { model.startRecording(row.key) },
                                        reset: { model.resetToDefault(row.key) })
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Spacer()
                Button("모두 기본값으로") { model.resetAll() }
            }
            Text("꺼진 기능의 단축키는 목록에 나오지 않습니다. 메뉴바에서 기능을 켜면 나타납니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .onDisappear { model.stopRecording() }
    }
}

private struct ShortcutRow: View {
    let row: HotkeyCenter.Registration
    let isRecording: Bool
    let record: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                if let note = row.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.combo != nil && !row.isRegistered && !isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("다른 앱이 이미 쓰고 있는 조합입니다")
            }
            Button(action: record) {
                Text(isRecording ? "입력 대기…" : (row.combo?.display ?? "사용 안 함"))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            Button(action: reset) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("기본값 \(row.defaultCombo.display)")
            .disabled(row.combo == row.defaultCombo)
        }
    }
}
