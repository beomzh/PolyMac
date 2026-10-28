import AppKit
import PolyMacCore
import SwiftUI

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

    /// 모듈 id → 현재 언어의 이름 (언어를 바꾸면 달라진다)
    private let moduleName: (String) -> String
    private var monitor: Any?

    init(moduleName: @escaping (String) -> String) {
        self.moduleName = moduleName
        reload()
    }

    func reload() {
        let all = HotkeyCenter.shared.registrations
        var owners: [String] = []
        for r in all where !owners.contains(r.owner) { owners.append(r.owner) }
        groups = owners.map { owner in
            Group(id: owner, title: moduleName(owner), rows: all.filter { $0.owner == owner })
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

    func clear(_ key: String) {
        stopRecording()
        HotkeyCenter.shared.setCombo(nil, for: key)
        message = nil
        reload()
    }

    func resetAll() {
        stopRecording()
        HotkeyCenter.shared.resetAll()
        message = L("모든 단축키를 기본값으로 되돌렸습니다", "All shortcuts were reset to their defaults")
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
            message = L("⌘ · ⌃ · ⌥ 중 하나 이상과 함께 눌러 주세요 (F키는 단독 가능)", "Press with at least one of ⌘ ⌃ ⌥ (function keys work alone)")
            return
        }
        if let other = HotkeyCenter.shared.conflict(for: combo, excluding: key) {
            message = L("\(combo.display)은(는) '\(other.name)'에서 이미 쓰고 있습니다", "\(combo.display) is already used by '\(other.name)'")
            return
        }
        HotkeyCenter.shared.setCombo(combo, for: key)
        message = nil
        stopRecording()
        if let row = HotkeyCenter.shared.registrations.first(where: { $0.key == key }), !row.isRegistered {
            message = L("\(combo.display)은(는) 다른 앱이 이미 쓰고 있어 동작하지 않을 수 있습니다", "\(combo.display) is taken by another app and may not work")
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("바꿀 단축키를 클릭한 뒤 새 조합을 누르세요.  Esc 취소 · ⌫ 또는 ⓧ 버튼으로 지우기", "Click a shortcut, then press the new combination.  Esc cancels · ⌫ or the ⓧ button removes it"))
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(model.groups) { group in
                    Section(group.title) {
                        ForEach(group.rows) { row in
                            ShortcutRow(row: row, isRecording: model.recordingKey == row.key,
                                        record: { model.startRecording(row.key) },
                                        clear: { model.clear(row.key) },
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
                Button(L("모두 기본값으로", "Reset All")) { model.resetAll() }
            }
            Text(L("꺼진 기능의 단축키는 목록에 나오지 않습니다. \"기능\" 탭에서 켜면 나타납니다.", "Shortcuts of disabled features are hidden. Turn them on in the Features tab."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .onDisappear { model.stopRecording() }
    }
}

private struct ShortcutRow: View {
    let row: HotkeyCenter.Registration
    let isRecording: Bool
    let record: () -> Void
    let clear: () -> Void
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
                    .help(L("다른 앱이 이미 쓰고 있는 조합입니다", "Another app already uses this combination"))
            }
            Button(action: record) {
                Text(isRecording ? L("입력 대기…", "Press keys…") : (row.combo?.display ?? L("사용 안 함", "Off")))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            Button(action: clear) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(L("단축키 지우기 (사용 안 함)", "Remove shortcut (off)"))
            .disabled(row.combo == nil)
            Button(action: reset) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help(L("기본값 \(row.defaultCombo?.display ?? "없음")", "Default \(row.defaultCombo?.display ?? "none")"))
            .disabled(row.combo == row.defaultCombo)
        }
    }
}
