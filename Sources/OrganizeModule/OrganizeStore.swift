import AppKit
import PolyMacCore
import SwiftUI

/// 자동 정리 설정 파일(organize.json) 읽기·쓰기. 기능이 꺼져 있어도 환경 설정에서 규칙을 고칠 수 있게 모듈 밖에 둔다.
public enum OrganizeStore {
    /// 환경 설정에서 저장하면 보낸다 — 켜져 있는 모듈이 다시 불러온다
    public static let didChange = Notification.Name("dev.polymac.organize.settingsChanged")

    public static var url: URL { AppPaths.dataDirectory.appendingPathComponent("organize.json") }

    /// 파일이 없으면 기본값(프리셋 모두 꺼짐, 미리보기 모드). 사용자가 고친 파일이 깨졌으면 덮어쓰지 않고 오류.
    public static func load() throws -> OrganizeSettings {
        guard let data = try? Data(contentsOf: url) else { return OrganizeSettings() }
        let decoded: OrganizeSettings
        do {
            decoded = try JSONDecoder().decode(OrganizeSettings.self, from: data)
        } catch {
            throw ModuleError(L("규칙 파일을 읽지 못했습니다 (organize.json): \(error.localizedDescription)", "Could not read the rules file (organize.json): \(error.localizedDescription)"))
        }
        guard decoded.schemaVersion <= OrganizeSettings.currentSchemaVersion else {
            throw ModuleError(L("규칙 파일이 더 새 버전의 PolyMac에서 만들어졌습니다. 앱을 업데이트하세요.", "The rules file was made by a newer PolyMac. Please update the app."))
        }
        return decoded
    }

    /// notify: 환경 설정에서 저장할 때만 true (모듈 자신의 저장은 알리지 않아 되풀이되지 않게)
    public static func save(_ settings: OrganizeSettings, notify: Bool) throws {
        let encoder = JSONEncoder()
        // 키 순서를 고정해 사용자가 편집할 때 매번 같은 모양이 되게
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try AppPaths.writePrivate(try encoder.encode(settings), to: url)
        if notify { NotificationCenter.default.post(name: didChange, object: nil) }
    }

    /// JSON 파일을 텍스트 편집기로 (없으면 기본값으로 만든 뒤)
    @MainActor
    public static func openJSON() {
        if !FileManager.default.fileExists(atPath: url.path) { try? save(OrganizeSettings(), notify: false) }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
    }
}

/// 환경 설정 › 자동 정리 탭. 열 때 파일에서 읽고, 저장하면 파일에 쓰고 켜진 모듈에 알린다.
public struct OrganizeRulesPane: View {
    @StateObject private var holder = Holder()

    public init() {}

    public var body: some View {
        Group {
            if let model = holder.model {
                OrganizeEditorView(model: model, close: nil)
            } else {
                VStack(spacing: 12) {
                    Label(holder.error ?? "", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    HStack {
                        Button(L("JSON으로 편집…", "Edit as JSON…")) { OrganizeStore.openJSON() }
                        Button(L("다시 읽기", "Reload")) { holder.reload() }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @MainActor
    final class Holder: ObservableObject {
        @Published var model: OrganizeEditorModel?
        @Published var error: String?

        init() { reload() }

        func reload() {
            do {
                let settings = try OrganizeStore.load()
                error = nil
                model = OrganizeEditorModel(settings: settings, onSave: { new in
                    var toSave = new
                    // 켜짐 여부는 모듈이 관리 — 파일에 있던 값을 그대로 둔다
                    toSave.isEnabled = (try? OrganizeStore.load().isEnabled) ?? new.isEnabled
                    do {
                        try OrganizeStore.save(toSave, notify: true)
                        Toast.show(L("규칙을 저장했습니다", "Rules saved"),
                                   content: L("켜진 규칙 \(toSave.rules.filter(\.isEnabled).count)개 / 전체 \(toSave.rules.count)개", "\(toSave.rules.filter(\.isEnabled).count) of \(toSave.rules.count) rules on"))
                    } catch {
                        Toast.show(L("규칙을 저장하지 못했습니다", "Could not save rules"), content: error.localizedDescription, duration: 4)
                    }
                }, openJSON: { OrganizeStore.openJSON() })
            } catch {
                model = nil
                self.error = error.localizedDescription
            }
        }
    }
}
