import AppKit
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
                ForEach(UninstallerModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.mode) { _, mode in
                model.checked = []
                if mode == .orphans, model.orphanGroups.isEmpty { model.scanOrphans() }
                if mode == .apps, let app = model.selectedApp { model.scan(app) }
            }

            if model.mode == .apps {
                TextField("앱 검색", text: $model.query)
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
                Text("앱을 이 창에 끌어다 놓아도 됩니다")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("이미 지운 앱의 흔적").font(.headline)
                    Text("앱은 지웠는데 설정·캐시·데이터가 남은 것을 찾습니다. 앱 ID(com.회사.앱) 형태의 이름 중 이 Mac에 그 앱이 없는 것만 보여 줍니다. macOS 기본 항목은 제외합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        model.scanOrphans()
                    } label: {
                        Label("다시 찾기", systemImage: "arrow.clockwise")
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
                    itemList(groups: Dictionary(grouping: model.items, by: \.kind)
                        .sorted { LeftoverItem.Kind.allCases.firstIndex(of: $0.key)! < LeftoverItem.Kind.allCases.firstIndex(of: $1.key)! }
                        .map { (title: $0.key.title, note: $0.key.explanation, items: $0.value, group: nil as LeftoverScanner.OrphanGroup?) })
                } else {
                    placeholder("왼쪽에서 지울 앱을 고르거나, 앱을 이 창에 끌어다 놓으세요.", symbol: "trash.square")
                }
            } else {
                itemList(groups: model.orphanGroups.map { g in
                    (title: g.bundleID, note: g.items.first?.reason ?? "", items: g.items, group: g)
                })
            }
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
                Text([app.version.map { "버전 \($0)" }, app.bundleID, app.teamID.map { "개발사 팀 \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if model.isSelectedAppRunning {
                    Label("지금 실행 중 — 지울 때 먼저 종료합니다", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func itemList(groups: [(title: String, note: String, items: [LeftoverItem], group: LeftoverScanner.OrphanGroup?)]) -> some View {
        Group {
            if model.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("찾는 중…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                placeholder(model.mode == .orphans ? "남아 있는 흔적이 없습니다" : "남은 파일이 없습니다", symbol: "checkmark.seal")
            } else {
                List {
                    ForEach(groups, id: \.title) { g in
                        Section {
                            ForEach(g.items) { item in row(item) }
                        } header: {
                            HStack(alignment: .firstTextBaseline) {
                                if let orphan = g.group {
                                    Toggle("", isOn: Binding(
                                        get: { Set(orphan.items.map(\.id)).isSubset(of: model.checked) },
                                        set: { _ in model.toggleGroup(orphan) }
                                    ))
                                    .toggleStyle(.checkbox).labelsHidden()
                                }
                                Text(g.title).font(.headline)
                                Text("\(g.items.count)개 · \(size(g.items.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }))")
                                    .font(.caption).foregroundStyle(.secondary)
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
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.checked.contains(item.id) }, set: { _ in model.toggle(item) }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text((item.url.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.reason)
                    if item.requiresAdmin { Label("암호 필요", systemImage: "lock.fill") }
                }
                .font(.caption).foregroundStyle(.secondary)
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
            .help("Finder에서 보기")
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
            .help(c == .exact ? "앱 ID와 정확히 일치 — 이 앱의 것이 확실합니다"
                  : c == .likely ? "같은 개발사·설치 기록·앱 이름 등으로 이 앱의 것으로 보입니다"
                  : "이름만 비슷합니다 — 확인하고 직접 고르세요")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text("선택 \(model.checkedItems.count)개 · \(size(model.checkedSize))")
                .font(.callout.monospacedDigit())
            Button(role: .destructive) {
                model.askConfirm = true
            } label: {
                if model.isDeleting { ProgressView().controlSize(.small) } else { Text("휴지통으로 이동") }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.checkedItems.isEmpty || model.isDeleting)
            .confirmationDialog("선택한 \(model.checkedItems.count)개를 휴지통으로 옮길까요?", isPresented: $model.askConfirm) {
                Button("휴지통으로 이동", role: .destructive) { model.deleteChecked() }
            } message: {
                Text("Finder 휴지통으로 옮기므로 \"되돌려 놓기\"로 복구할 수 있습니다." + (model.checkedItems.contains { $0.requiresAdmin } ? " 일부 항목은 관리자 암호를 묻습니다." : ""))
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

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
