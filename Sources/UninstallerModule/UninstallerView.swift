import AppKit
import PolyMacCore
import SwiftUI
import UninstallerCore
import UniformTypeIdentifiers

struct UninstallerView: View {
    @ObservedObject var model: UninstallerModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { model.select(appAt: url) } }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
    }

    // MARK: - 왼쪽

    private var sidebar: some View {
        VStack(spacing: 8) {
            Picker("", selection: $model.mode) {
                ForEach(UninstallerModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.mode) { _, mode in
                model.checked = []
                if mode == .orphans, model.orphanGroups.isEmpty { model.scanOrphans() }
                if mode == .apps, let app = model.selectedApp { model.scan(app) }
            }

            if model.mode == .apps {
                TextField(L("앱 검색", "Search apps"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                List(model.filteredApps, selection: $model.selectedAppID) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text(app.bundleID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(app.id)
                }
                .listStyle(.sidebar)
                Text(L("앱을 이 창에 끌어다 놓아도 됩니다", "You can also drop an app on this window"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("이미 지운 앱의 흔적", "Leftovers of removed apps")).font(.headline)
                    Text(L("앱은 지웠는데 설정·캐시·데이터가 남은 것을 찾습니다. 앱 ID(com.회사.앱) 형태의 이름 중 이 Mac에 그 앱이 없는 것만 보여 줍니다. macOS 기본 항목은 제외합니다.", "Finds settings, caches and data left behind by apps you already removed. Only names shaped like an app ID (com.vendor.app) whose app is not on this Mac are shown. macOS items are excluded."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        model.scanOrphans()
                    } label: {
                        Label(L("다시 찾기", "Scan Again"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
    }

    // MARK: - 오른쪽

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if model.mode == .apps {
                if let app = model.selectedApp {
                    appHeader(app)
                    Divider()
                    selectionBar
                    itemList(groups: Dictionary(grouping: model.items, by: \.kind)
                        .sorted { LeftoverItem.Kind.allCases.firstIndex(of: $0.key)! < LeftoverItem.Kind.allCases.firstIndex(of: $1.key)! }
                        .map { (id: $0.key.rawValue, title: $0.key.title, note: $0.key.explanation, items: $0.value) })
                } else {
                    placeholder(L("왼쪽에서 지울 앱을 고르거나, 앱을 이 창에 끌어다 놓으세요.", "Pick an app on the left, or drop one on this window."), symbol: "trash.square")
                }
            } else {
                selectionBar
                itemList(groups: model.vendorGroups.map { (id: $0.id, title: $0.title, note: $0.note, items: $0.items) })
            }
            leftBehindNotice
            Divider()
            footer
        }
    }

    private func appHeader(_ app: AppBundleInfo) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.weight(.semibold))
                Text([app.version.map { L("버전 \($0)", "Version \($0)") }, app.bundleID, app.teamID.map { L("개발사 팀 \($0)", "Team \($0)") }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("마지막 사용: ", "Last used: ") + (model.appLastUsed.map(dateText) ?? L("기록 없음", "unknown")))
                    .font(.caption).foregroundStyle(.secondary)
                if model.isSelectedAppRunning {
                    Label(L("지금 실행 중 — 지울 때 먼저 종료합니다", "Running now — it will be quit before removal"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    /// 전체 선택 · 전체 해제 · 유력만
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button(L("전체 선택", "Select All")) { model.selectAll() }
            Button(L("전체 해제", "Select None")) { model.deselectAll() }
            Button(L("확실·유력만", "Certain & Likely Only")) { model.selectLikely() }
                .help(L("이름만 비슷한 '추정' 항목은 빼고 고릅니다", "Selects everything except 'possible' items that only have a similar name"))
            Spacer()
            if model.mode == .orphans {
                Text(L("\(model.vendorGroups.count)개 앱의 흔적", "Leftovers of \(model.vendorGroups.count) apps")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(model.isScanning || model.currentItems.isEmpty)
    }

    private func itemList(groups: [(id: String, title: String, note: String, items: [LeftoverItem])]) -> some View {
        Group {
            if model.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L("찾는 중…", "Searching…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                placeholder(model.mode == .orphans ? L("남아 있는 흔적이 없습니다", "No leftovers") : L("남은 파일이 없습니다", "No files left"), symbol: "checkmark.seal")
            } else {
                List {
                    ForEach(groups, id: \.id) { g in
                        Section {
                            ForEach(g.items) { item in row(item) }
                        } header: {
                            HStack(alignment: .firstTextBaseline) {
                                // 묶음(앱·종류) 단위로 한 번에 선택·해제. 일부만 고른 상태는 "–"로
                                Toggle("", isOn: Binding(
                                    get: { model.isAllChecked(g.items) },
                                    set: { _ in model.toggleItems(g.items) }
                                ))
                                .toggleStyle(.checkbox).labelsHidden()
                                .overlay {
                                    if model.isPartlyChecked(g.items) {
                                        Image(systemName: "minus").font(.system(size: 9, weight: .bold)).allowsHitTesting(false)
                                    }
                                }
                                Text(g.title).font(.headline)
                                Text(L("\(g.items.count)개 · \(size(g.items.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }))", "\(g.items.count) items · \(size(g.items.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }))"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let newest = g.items.compactMap({ model.modified[$0.id] }).max() {
                                    Text(L("· 최근 수정 ", "· modified ") + dateText(newest)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if !g.note.isEmpty {
                                Text(g.note).font(.caption).foregroundStyle(.secondary).textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func row(_ item: LeftoverItem) -> some View {
        let user = model.inUse[item.id]
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.checked.contains(item.id) && user == nil }, set: { _ in model.toggle(item) }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(user != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text((item.url.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(user == nil ? .primary : .secondary)
                HStack(spacing: 6) {
                    if model.mode == .orphans, let id = model.orphanIDs[item.id], !id.contains(" ") { Text(id + " ·") }
                    Text(item.reason)
                    if item.requiresAdmin { Label(L("암호 필요", "Password"), systemImage: "lock.fill") }
                    if let date = model.modified[item.id] { Text(L("· 수정 ", "· modified ") + dateText(date)) }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let user {
                    Label(L("사용 중 (\(user)) — 지우지 않습니다. 그 프로그램을 끄고 다시 찾으세요", "In use (\(user)) — won't be removed. Quit that program and scan again"), systemImage: "lock.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            badge(item.confidence)
            Text(model.sizes[item.id].map(size) ?? "…")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L("Finder에서 보기", "Show in Finder"))
        }
        .padding(.vertical, 2)
    }

    private func badge(_ c: LeftoverItem.Confidence) -> some View {
        let tint: Color = c == .exact ? .green : (c == .likely ? .orange : .gray)
        return Text(c.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
            .help(c == .exact ? L("앱 ID와 정확히 일치 — 이 앱의 것이 확실합니다", "Matches the app ID exactly — certainly this app's")
                  : c == .likely ? L("같은 개발사·설치 기록·앱 이름 등으로 이 앱의 것으로 보입니다", "Same developer, install record or app name — very likely this app's")
                  : L("이름만 비슷합니다 — 확인하고 직접 고르세요", "Only the name is similar — check before selecting"))
    }

    /// 휴지통으로 못 옮긴 항목 안내 — Finder에서 열어 직접 옮기게 한다
    @ViewBuilder private var leftBehindNotice: some View {
        if !model.leftBehind.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("\(model.leftBehind.count)개를 휴지통으로 옮기지 못했습니다", "\(model.leftBehind.count) item(s) could not be moved to the Trash")).font(.callout.weight(.semibold))
                    Text(L("\"Finder에서 열기\"를 누르면 그 항목을 골라 둔 채로 Finder가 열립니다. 휴지통으로 끌어다 놓거나 ⌘⌫를 누르세요.", "\"Show in Finder\" opens Finder with them selected. Drag them to the Trash or press ⌘⌫."))
                        .font(.caption)
                    if model.leftBehindHasContainers {
                        Text(L("Containers 안의 앱 데이터 폴더는 macOS가 폴더 자체를 지켜 Finder에서도 거절될 수 있습니다. 앱이 없으면 비어 있는 껍데기라 그냥 둬도 됩니다.", "macOS protects app data folders in Containers, so even Finder may refuse. If the app is gone it's an empty shell and can safely stay."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(model.leftBehind.prefix(3).map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button(L("Finder에서 열기", "Show in Finder")) { model.revealLeftBehind() }
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12).padding(.top, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            } else if model.isCheckingUse {
                ProgressView().controlSize(.small)
                Text(L("사용 중인 파일 확인 중…", "Checking for files in use…")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(L("선택 \(model.checkedItems.count)개 · \(size(model.checkedSize))", "\(model.checkedItems.count) selected · \(size(model.checkedSize))"))
                .font(.callout.monospacedDigit())
            Button(role: .destructive) {
                model.askConfirm = true
            } label: {
                if model.isDeleting { ProgressView().controlSize(.small) } else { Text(L("휴지통으로 이동", "Move to Trash")) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.checkedItems.isEmpty || model.isDeleting || model.isCheckingUse)
            .confirmationDialog(L("선택한 \(model.checkedItems.count)개를 휴지통으로 옮길까요?", "Move the \(model.checkedItems.count) selected item(s) to the Trash?"), isPresented: $model.askConfirm) {
                Button(L("휴지통으로 이동", "Move to Trash"), role: .destructive) { model.deleteChecked() }
            } message: {
                Text(L("Finder 휴지통으로 옮기므로 \"되돌려 놓기\"로 복구할 수 있습니다.", "Items go to the Finder Trash, so \"Put Back\" can restore them.") + (model.checkedItems.contains { $0.requiresAdmin } ? L(" 일부 항목은 관리자 암호를 묻습니다.", " Some items will ask for an administrator password.") : ""))
            }
        }
        .padding(12)
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "2026. 10. 21. (6일 전)"
    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted) + " (" + date.formatted(.relative(presentation: .named)) + ")"
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
