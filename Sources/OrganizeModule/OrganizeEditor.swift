import AppKit
import PolyMacCore
import SwiftUI
import UniformTypeIdentifiers

/// 편집 중인 규칙. 저장할 때 OrganizeRule로 바꾼다.
struct RuleDraft: Identifiable, Equatable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var match: MatchMode
    var conditions: [ConditionRow]
    var actions: [ActionRow]
    var stopAfterMatch: Bool

    init(_ rule: OrganizeRule) {
        id = rule.id
        name = rule.name
        isEnabled = rule.isEnabled
        match = rule.match
        conditions = rule.conditions.map(ConditionRow.init)
        actions = rule.actions.map(ActionRow.init)
        stopAfterMatch = rule.stopAfterMatch
    }

    var rule: OrganizeRule {
        OrganizeRule(id: id, name: name.trimmingCharacters(in: .whitespaces), isEnabled: isEnabled, match: match,
                     conditions: conditions.compactMap(\.condition), actions: actions.compactMap(\.action),
                     stopAfterMatch: stopAfterMatch)
    }

    /// 조건·동작이 하나도 없으면 저장하지 못하게
    var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return L("이름이 비어 있습니다", "Name is empty") }
        if rule.conditions.isEmpty { return L("조건이 없습니다 (값이 빈 조건은 빠집니다)", "No conditions (empty ones are dropped)") }
        if rule.actions.isEmpty { return L("동작이 없습니다", "No actions") }
        return nil
    }
}

@MainActor
final class OrganizeEditorModel: ObservableObject {
    @Published var rules: [RuleDraft]
    @Published var selection: UUID?
    @Published var folders: [WatchedFolder]
    @Published var dryRun: Bool
    @Published var settleDelay: Double
    private var base: OrganizeSettings
    private let onSave: (OrganizeSettings) -> Void
    let openJSON: () -> Void

    init(settings: OrganizeSettings, onSave: @escaping (OrganizeSettings) -> Void, openJSON: @escaping () -> Void) {
        base = settings
        rules = settings.rules.map(RuleDraft.init)
        folders = settings.watchedFolders
        dryRun = settings.dryRun
        settleDelay = settings.settleDelay
        selection = settings.rules.first?.id
        self.onSave = onSave
        self.openJSON = openJSON
    }

    var problems: [String] {
        rules.compactMap { draft in draft.problem.map { "'\(draft.name)': \($0)" } }
    }

    func addRule() {
        var draft = RuleDraft(OrganizeRule(name: L("새 규칙", "New Rule"), conditions: [], actions: []))
        draft.conditions = [ConditionRow(kind: .fileExtension)]
        draft.actions = [ActionRow(kind: .move, text: "~/Downloads/{kind}")]
        rules.append(draft)
        selection = draft.id
    }

    func addPresets() {
        let names = Set(rules.map(\.name))
        for preset in OrganizePresets.all where !names.contains(preset.name) {
            rules.append(RuleDraft(preset))
        }
    }

    func remove(_ id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules.remove(at: index)
        selection = rules.isEmpty ? nil : rules[min(index, rules.count - 1)].id
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = rules.firstIndex(where: { $0.id == id }), rules.indices.contains(i + offset) else { return }
        rules.swapAt(i, i + offset)
    }

    /// 목록에서 끌어 옮기기 — 위에 있는 규칙부터 검사한다
    func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
    }

    /// 지금 편집 중인 규칙(저장 전 고친 것 포함)을 규칙 파일로
    func exportRules() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PolyMac-rules.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message = L("감시 폴더·미리보기 모드는 빼고 규칙만 저장합니다.", "Only rules are saved, not watched folders or preview mode.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try RuleTransfer.encode(rules.map(\.rule)).write(to: url, options: .atomic)
            Toast.show(L("규칙 \(rules.count)개를 내보냈습니다", "Exported \(rules.count) rules"), content: url.lastPathComponent)
        } catch {
            Toast.show(L("내보내지 못했습니다", "Could not export"), content: error.localizedDescription, duration: 4)
        }
    }

    /// 규칙 파일이나 organize.json에서 읽어 꺼진 상태로 넣는다. 저장을 눌러야 파일에 반영된다.
    func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = L("가져온 규칙은 꺼진 상태로 들어갑니다. 확인하고 켠 뒤 저장하세요.", "Imported rules come in turned off. Review, turn on, then Save.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported: [OrganizeRule]
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= RuleTransfer.maxBytes else { throw ModuleError(L("파일이 너무 큽니다 (1MB 넘음)", "The file is too large (over 1 MB)")) }
            imported = try RuleTransfer.decode(Data(contentsOf: url), existingIDs: Set(rules.map(\.id)))
        } catch {
            Toast.show(L("가져오지 못했습니다", "Could not import"), content: error.localizedDescription, duration: 5)
            return
        }
        guard !imported.isEmpty else {
            Toast.show(L("가져올 규칙이 없습니다", "No rules to import"), content: url.lastPathComponent)
            return
        }

        var replace = false
        if !rules.isEmpty {
            let alert = NSAlert()
            alert.messageText = L("규칙 \(imported.count)개를 가져옵니다", "Import \(imported.count) rules")
            alert.informativeText = L("지금 규칙 \(rules.count)개 뒤에 붙이거나, 지금 규칙을 모두 바꿀 수 있습니다. 가져온 규칙은 꺼진 상태이며 저장을 눌러야 적용됩니다.",
                                      "Add them after your \(rules.count) rules, or replace all of them. Imported rules are off and apply only after you Save.")
            alert.addButton(withTitle: L("뒤에 붙이기", "Add"))
            alert.addButton(withTitle: L("모두 바꾸기", "Replace All"))
            alert.addButton(withTitle: L("취소", "Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: break
            case .alertSecondButtonReturn: replace = true
            default: return
            }
        }
        if replace { rules.removeAll() }
        rules.append(contentsOf: imported.map(RuleDraft.init))
        selection = imported.first?.id
        Toast.show(L("규칙 \(imported.count)개를 가져왔습니다 (꺼짐)", "Imported \(imported.count) rules (off)"),
                   content: L("확인하고 켠 뒤 저장을 누르세요", "Review, turn on, then press Save"))
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("감시하기", "Watch")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = (url.path as NSString).abbreviatingWithTildeInPath
            if !folders.contains(where: { $0.path == path }) { folders.append(WatchedFolder(path: path)) }
        }
    }

    func save() {
        var settings = base
        settings.rules = rules.map(\.rule)
        settings.watchedFolders = folders
        settings.dryRun = dryRun
        settings.settleDelay = max(settleDelay, 1)
        base = settings
        onSave(settings)
    }
}

struct OrganizeEditorView: View {
    @ObservedObject var model: OrganizeEditorModel
    /// 따로 띄운 창이면 닫기 버튼, 환경 설정 탭에 넣으면 nil
    let close: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ruleList.frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
                detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer.padding(12)
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    // MARK: - 왼쪽: 규칙 목록 + 감시 폴더

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $model.selection) {
                Section(L("규칙 (위에서부터 검사, 끌어서 순서 바꾸기)", "Rules (checked top to bottom, drag to reorder)")) {
                    ForEach($model.rules) { $rule in
                        HStack {
                            Toggle("", isOn: $rule.isEnabled).labelsHidden().toggleStyle(.checkbox)
                            Text(rule.name.isEmpty ? L("(이름 없음)", "(untitled)") : rule.name)
                                .lineLimit(1)
                                .foregroundStyle(rule.problem == nil ? .primary : Color.red)
                        }
                        .tag(rule.id)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
            }
            HStack(spacing: 4) {
                Button { model.addRule() } label: { Image(systemName: "plus") }
                    .help(L("규칙 추가", "Add rule"))
                Button { if let id = model.selection { model.remove(id) } } label: { Image(systemName: "minus") }
                    .disabled(model.selection == nil)
                    .help(L("규칙 삭제", "Delete rule"))
                Button { if let id = model.selection { model.move(id, by: -1) } } label: { Image(systemName: "chevron.up") }
                    .disabled(model.selection == nil)
                    .help(L("위로", "Move up"))
                Button { if let id = model.selection { model.move(id, by: 1) } } label: { Image(systemName: "chevron.down") }
                    .disabled(model.selection == nil)
                    .help(L("아래로", "Move down"))
                Spacer()
                Menu(L("더 보기", "More")) {
                    Button(L("빠진 기본 규칙 다시 넣기 (꺼진 상태)", "Add missing presets (off)")) { model.addPresets() }
                    Divider()
                    Button(L("규칙 가져오기…", "Import Rules…")) { model.importRules() }
                    Button(L("규칙 내보내기…", "Export Rules…")) { model.exportRules() }
                        .disabled(model.rules.isEmpty || !model.problems.isEmpty)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(8)
            Divider()
            folderSection.padding(8)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("감시 폴더 (바로 아래 파일만)", "Watched folders (top level only)")).font(.headline)
            ForEach($model.folders, id: \.path) { $folder in
                HStack {
                    Toggle("", isOn: $folder.isEnabled).labelsHidden().toggleStyle(.checkbox)
                    Text(folder.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { model.folders.removeAll { $0.path == folder.path } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            Button(L("폴더 추가…", "Add Folder…")) { model.addFolder() }
        }
    }

    // MARK: - 오른쪽: 고른 규칙

    @ViewBuilder
    private var detail: some View {
        if let index = model.rules.firstIndex(where: { $0.id == model.selection }) {
            RuleDetail(rule: $model.rules[index])
                .id(model.rules[index].id)
        } else {
            Text(L("왼쪽에서 규칙을 고르거나 + 로 추가하세요", "Pick a rule on the left or add one with +"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 아래

    private var footer: some View {
        HStack {
            Toggle(L("미리보기 모드 (옮기지 않고 기록만)", "Preview mode (log only)"), isOn: $model.dryRun)
            Stepper(value: $model.settleDelay, in: 1...600, step: 5) {
                Text(L("받은 뒤 \(Int(model.settleDelay))초 기다림", "Wait \(Int(model.settleDelay))s after download"))
            }
            .help(L("다운로드가 끝나기 전에 옮기지 않도록", "So files aren't moved before the download finishes"))
            Spacer()
            if let first = model.problems.first {
                Label(first, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(model.problems.joined(separator: "\n"))
            }
            Button(L("JSON으로 편집…", "Edit as JSON…")) { model.openJSON() }
            if let close {
                Button(L("닫기", "Close")) { close() }
                    .keyboardShortcut(.cancelAction)
            }
            Button(L("저장", "Save")) { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.problems.isEmpty)
        }
    }
}

private struct RuleDetail: View {
    @Binding var rule: RuleDraft

    var body: some View {
        Form {
            Section {
                LabeledContent(L("이름", "Name")) {
                    InputBox(L("규칙 이름", "Rule name"), text: $rule.name)
                }
                Toggle(L("켜기", "Enabled"), isOn: $rule.isEnabled)
                Toggle(L("이 규칙이 적용되면 다음 규칙은 건너뛰기", "Stop checking later rules after this one applies"), isOn: $rule.stopAfterMatch)
            }
            Section {
                Picker(L("조건", "Conditions"), selection: $rule.match) {
                    Text(L("모두 맞을 때", "All match")).tag(MatchMode.all)
                    Text(L("하나라도 맞을 때", "Any matches")).tag(MatchMode.any)
                }
                .pickerStyle(.segmented)
                ForEach($rule.conditions) { $row in
                    ConditionEditor(row: $row) { rule.conditions.removeAll { $0.id == row.id } }
                }
                Button(L("조건 추가", "Add Condition")) { rule.conditions.append(ConditionRow()) }
            } header: {
                Text(L("조건", "Conditions"))
            }
            Section {
                ForEach($rule.actions) { $row in
                    ActionEditor(row: $row) { rule.actions.removeAll { $0.id == row.id } }
                }
                Button(L("동작 추가", "Add Action")) { rule.actions.append(ActionRow()) }
                Text(L("폴더·이름에 쓸 수 있는 값: {name} {ext} {kind} {domain} {yyyy} {MM} {dd}. 홈 폴더 밖으로는 옮기지 않습니다.",
                       "Placeholders for folders and names: {name} {ext} {kind} {domain} {yyyy} {MM} {dd}. Files are never moved outside your home folder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("동작 (차례대로)", "Actions (in order)"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConditionEditor: View {
    @Binding var row: ConditionRow
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $row.kind) {
                    ForEach(ConditionRow.Kind.allCases, id: \.self) { Text(ConditionRow.title($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle(L("아님", "Not"), isOn: $row.negated).toggleStyle(.checkbox)
                Spacer()
                Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
            switch row.kind {
            case .fileExtension:
                InputBox(L("pdf, hwp, zip (쉼표로 구분)", "pdf, docx, zip (comma separated)"), text: $row.text)
            case .sourceDomain:
                InputBox(L("go.kr, github.com (하위 도메인 포함)", "github.com, example.org (includes subdomains)"), text: $row.text)
            case .name:
                HStack {
                    InputBox(L("*견적서*", "*invoice*"), text: $row.text)
                    Toggle(L("정규식", "Regex"), isOn: $row.isRegex).toggleStyle(.checkbox)
                }
            case .kind:
                HStack {
                    ForEach(FileKind.allCases, id: \.self) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { row.kinds.contains(kind) },
                            set: { on in if on { row.kinds.insert(kind) } else { row.kinds.remove(kind) } }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            case .sizeGreaterThan, .sizeLessThan, .addedMoreThan, .notOpenedFor:
                HStack {
                    TextField("", value: $row.number, format: .number, prompt: Text("0"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    if [.sizeGreaterThan, .sizeLessThan].contains(row.kind) {
                        Text("MB").foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: $row.timeUnit) {
                            ForEach(ConditionRow.TimeUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help(L("1개월은 30일, 1년은 365일로 셉니다", "A month counts as 30 days, a year as 365 days"))
                    }
                    Spacer()
                }
            case .allFiles:
                Text(L("감시 폴더 바로 아래의 모든 파일 (다운로드 중인 파일·폴더 제외). 다른 조건과 \"모두 맞을 때\"로 묶으면 그 조건만 남습니다.",
                       "Every file directly in the watched folders (except downloads in progress and folders). Combined with \"All match\", only the other conditions matter."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .isDuplicate:
                Text(L("\"이름 (1).pdf\"처럼 번호가 붙었고 원래 파일과 내용이 똑같을 때", "Numbered copies like \"name (1).pdf\" whose content equals the original"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActionEditor: View {
    @Binding var row: ActionRow
    let remove: () -> Void

    var body: some View {
        HStack {
            Picker("", selection: $row.kind) {
                ForEach(ActionRow.Kind.allCases, id: \.self) { Text(ActionRow.title($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            if row.needsText {
                InputBox(placeholder, text: $row.text)
                if row.kind == .move || row.kind == .copy {
                    Button(L("고르기…", "Choose…")) { choose() }
                }
            } else {
                Spacer()
            }
            Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
        }
    }

    private var placeholder: String {
        switch row.kind {
        case .move, .copy: return "~/Documents/{yyyy}-{MM}"
        case .rename: return "{yyyy}{MM}{dd}_{name}.{ext}"
        case .addTag: return L("빨간색", "Red")
        default: return ""
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        row.text = (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// 테두리 있는 입력 칸. grouped Form 안의 TextField는 기본이 테두리 없는 글자라 입력 칸으로 보이지 않는다 —
/// 자리표시 글은 칸 안에 흐리게, 이름표는 따로 두지 않는다.
private struct InputBox: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading) // grouped Form은 오른쪽 정렬이 기본
            .frame(maxWidth: .infinity)
    }
}
