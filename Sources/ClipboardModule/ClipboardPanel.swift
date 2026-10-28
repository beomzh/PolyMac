import AppKit
import ImageIO
import PolyMacCore
import SwiftUI

/// 클립보드 히스토리 창. 평소에는 좁은 목록만, ⌘→ 또는 오른쪽 위 버튼으로 미리보기 패널을 옆으로 펼친다.
/// 앞에 있던 앱의 포커스를 빼앗지 않는 패널이라 ⇧↩︎로 그 앱에 바로 붙여넣을 수 있다.
/// 창과 화면은 처음 열 때 한 번만 만들고 닫을 때는 숨기기만 한다 — 다시 열 때 바로 뜨게 (측정: 새로 만들면 약 100 ms)
@MainActor
final class ClipboardPanelController {
    struct Callbacks {
        /// pasteNow == false: 클립보드로 복사만 (기본), true: 복사 후 앞의 앱에 바로 붙여넣기 (⇧↩︎)
        let choose: (ClipboardItem, _ pasteNow: Bool) -> Void
        let togglePin: (UUID) -> Void
        let delete: (UUID) -> Void
    }

    static let listWidth: CGFloat = 400
    static let previewWidth: CGFloat = 380
    static let height: CGFloat = 520
    private static let previewKey = "clipboard.previewOpen"

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var model: ClipboardPanelModel?
    private var callbacks: Callbacks?

    var isOpen: Bool { panel?.isVisible == true }
    var isPrepared: Bool { model != nil }

    /// 모듈이 켜질 때: 화면은 아직 만들지 않고 목록·썸네일·앱 아이콘만 미리 준비
    func prepare(items: [ClipboardItem], imageDirectory: URL, textDirectory: URL) {
        let model = ClipboardPanelModel(items: items, imageDirectory: imageDirectory, textDirectory: textDirectory,
                                        previewOpen: UserDefaults.standard.bool(forKey: Self.previewKey))
        self.model = model
        model.prefetch()
    }

    func show(callbacks: Callbacks) {
        guard let model else { return }
        if isOpen { close(); return }
        self.callbacks = callbacks
        model.reset()
        let panel = self.panel ?? makePanel(model)
        self.panel = panel
        var frame = panel.frame
        frame.size = NSSize(width: width(model.previewOpen), height: Self.height)
        // 마우스가 있는 화면, 마우스 근처 (Maccy처럼)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(mouse.x - Self.listWidth / 2, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(mouse.y - Self.height + 40, visible.minY + 8), visible.maxY - Self.height - 8)
        }
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)

        // 목록 이동·복사 키는 검색창이 먹기 전에 가로챈다
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 로컬 모니터는 메인 스레드에서 불린다
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let callbacks = self.callbacks, event.window === self.panel else { return false }
                return self.handle(event, callbacks)
            }
            return handled ? nil : event
        }
        // 다른 곳을 클릭하면 닫는다
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func makePanel(_ model: ClipboardPanelModel) -> NSPanel {
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: NSSize(width: width(model.previewOpen), height: Self.height)),
                                 styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear

        model.onTogglePreview = { [weak self, weak panel, weak model] in
            guard let self, let panel, let model else { return }
            UserDefaults.standard.set(model.previewOpen, forKey: Self.previewKey)
            var frame = panel.frame
            frame.size.width = self.width(model.previewOpen)
            // 애니메이션을 쓰면 프레임마다 미리보기 전체를 다시 배치해 긴 텍스트에서 멈춘다
            panel.setFrame(frame, display: true, animate: false)
        }
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(model: model, onPick: { [weak self] item in
            guard let self else { return }
            let callbacks = self.callbacks
            self.close()
            callbacks?.choose(item, false)
        }))
        return panel
    }

    private func width(_ previewOpen: Bool) -> CGFloat {
        Self.listWidth + (previewOpen ? Self.previewWidth : 0)
    }

    /// 숨기기만 한다 (다음에 바로 뜨게)
    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
    }

    /// 모듈을 끌 때 창까지 버린다
    func tearDown() {
        close()
        panel?.contentView = nil
        panel = nil
        model = nil
    }

    func update(items: [ClipboardItem]) {
        model?.items = items
        model?.prefetch()
    }

    private func handle(_ event: NSEvent, _ callbacks: Callbacks) -> Bool {
        guard let model else { return false }
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case 53: close(); return true // Esc
        case 125: model.move(1); return true // ↓
        case 126: model.move(-1); return true // ↑
        case 124 where cmd, 123 where cmd: // ⌘→ ⌘← 미리보기 펼치기/접기
            model.setPreview(event.keyCode == 124)
            return true
        case 36, 76: // ↩︎ 복사 · ⇧↩︎ 바로 붙여넣기
            guard let item = model.selected else { return true }
            close()
            callbacks.choose(item, event.modifierFlags.contains(.shift))
            return true
        case 51 where cmd: // ⌘⌫ 삭제
            if let id = model.selected?.id { callbacks.delete(id); model.remove(id) }
            return true
        default:
            break
        }
        guard cmd, let key = event.latinKey else { return false }
        if key == "p", let id = model.selected?.id {
            callbacks.togglePin(id)
            model.togglePin(id)
            return true
        }
        // ⌘1~⌘9, ⌘0 = 10번째
        if let n = Int(key) {
            let index = n == 0 ? 9 : n - 1
            guard index < model.filtered.count else { return true }
            let item = model.filtered[index]
            close()
            callbacks.choose(item, false)
            return true
        }
        return false
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published var items: [ClipboardItem] {
        didSet { refilter() }
    }
    @Published var query = "" {
        didSet {
            refilter()
            selectedID = filtered.first?.id
        }
    }
    /// 걸러진 목록은 항목·검색어가 바뀔 때만 다시 만든다 (그릴 때마다 계산하면 행 수만큼 반복됨)
    @Published private(set) var filtered: [ClipboardItem] = []
    @Published var selectedID: UUID?
    @Published private(set) var previewOpen: Bool
    /// 백그라운드에서 읽어 온 썸네일 — 들어오면 해당 행만 다시 그려진다
    @Published private var thumbnails: [String: NSImage] = [:]
    var onTogglePreview: (() -> Void)?

    let imageDirectory: URL
    let textDirectory: URL
    private var loadingThumbnails = Set<String>()
    private var previewCache: (id: UUID, text: String, truncated: Bool)?

    init(items: [ClipboardItem], imageDirectory: URL, textDirectory: URL, previewOpen: Bool) {
        self.items = items
        self.imageDirectory = imageDirectory
        self.textDirectory = textDirectory
        self.previewOpen = previewOpen
        refilter()
        selectedID = filtered.first?.id
    }

    /// 창을 열 때마다: 검색어 지우고 맨 위 항목 선택
    func reset() {
        if !query.isEmpty { query = "" }
        selectedID = filtered.first?.id
    }

    /// 목록용 썸네일을 미리 만들어 둔다 (창을 열 때 회색 자리가 보이지 않게). 아이콘·앱 이름도 미리 찾는다.
    func prefetch() {
        for item in items where item.isImage { _ = thumbnail(item) }
        let apps = Set(items.compactMap(\.sourceApp))
        DispatchQueue.main.async {
            for id in apps { _ = AppInfo.icon(for: id); _ = AppInfo.name(for: id) }
        }
    }

    func setPreview(_ open: Bool) {
        guard open != previewOpen else { return }
        previewOpen = open
        onTogglePreview?()
    }

    /// 고정 항목 먼저, 그다음 최근 순. 띄어쓰기로 나눈 단어가 모두 들어 있는 항목만 (대소문자·한글 정규화 무시).
    /// "이미지"로 이미지만 찾기.
    private func refilter() {
        let ordered = items.filter(\.isPinned) + items.filter { !$0.isPinned }
        let words = query.precomposedStringWithCanonicalMapping.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { filtered = ordered; return }
        filtered = ordered.filter { item in
            let text = (item.isImage ? "이미지 image" : item.text).precomposedStringWithCanonicalMapping.lowercased()
            let app = AppInfo.name(for: item.sourceApp).lowercased()
            return words.allSatisfy { text.contains($0) || app.contains($0) }
        }
    }

    /// 지금 강조된 항목 id (선택이 없으면 첫 항목)
    var highlightedID: UUID? { selectedID ?? filtered.first?.id }

    var selected: ClipboardItem? {
        guard let id = highlightedID else { return nil }
        return filtered.first { $0.id == id }
    }

    func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let index = filtered.firstIndex { $0.id == highlightedID } ?? 0
        selectedID = filtered[min(max(index + delta, 0), filtered.count - 1)].id
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isPinned.toggle()
    }

    func remove(_ id: UUID) {
        let index = filtered.firstIndex { $0.id == id } ?? 0
        items.removeAll { $0.id == id }
        selectedID = filtered.isEmpty ? nil : filtered[min(index, filtered.count - 1)].id
    }

    /// 큰 텍스트 미리보기: 화면이 버벅이지 않게 앞 200 KB까지만 읽는다 (복사는 전체)
    static let previewLimit = 200 * 1024

    /// 같은 항목이면 파일을 다시 읽지 않는다
    func previewText(_ item: ClipboardItem) -> (text: String, truncated: Bool) {
        if let cache = previewCache, cache.id == item.id { return (cache.text, cache.truncated) }
        var result = (text: item.text, truncated: false)
        if let file = item.textFile, let handle = try? FileHandle(forReadingFrom: textDirectory.appendingPathComponent(file)) {
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: Self.previewLimit)) ?? Data()
            // 잘린 끝의 깨진 UTF-8 바이트는 버린다
            var text = String(decoding: data, as: UTF8.self)
            if text.hasSuffix("\u{FFFD}") { text.removeLast() }
            result = (text, (item.textBytes ?? 0) > Self.previewLimit)
        }
        previewCache = (item.id, result.text, result.truncated)
        return result
    }

    private func pruneThumbnails() {
        let live = Set(items.compactMap(\.imageFile))
        thumbnails = thumbnails.filter { key, _ in live.contains(String(key.split(separator: "@").first ?? "")) }
        loadingThumbnails = loadingThumbnails.filter { live.contains(String($0.split(separator: "@").first ?? "")) }
    }

    /// 목록·미리보기용 축소 이미지. 처음엔 nil을 돌려주고 백그라운드에서 읽어 오면 다시 그려진다
    /// (원본 전체를 메모리에 올리지 않게 ImageIO 축소본, 창을 닫으면 버림)
    func thumbnail(_ item: ClipboardItem, maxPixel: Int = 240) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        if thumbnails.count > 300 { pruneThumbnails() }
        let key = "\(file)@\(maxPixel)"
        if let cached = thumbnails[key] { return cached }
        guard loadingThumbnails.insert(key).inserted else { return nil }
        let url = imageDirectory.appendingPathComponent(file)
        Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { return }
            await MainActor.run {
                self.thumbnails[key] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        return nil
    }
}

/// 번들 ID → 앱 이름·아이콘 (한 번 찾으면 기억)
@MainActor
enum AppInfo {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static func name(for bundleID: String?) -> String {
        guard let bundleID else { return L("알 수 없음", "Unknown") }
        if let cached = names[bundleID] { return cached }
        var name = bundleID
        if bundleID == Bundle.main.bundleIdentifier {
            name = "PolyMac"
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        names[bundleID] = name
        return name
    }

    static func icon(for bundleID: String?) -> NSImage {
        let key = bundleID ?? ""
        if let cached = icons[key] { return cached }
        var image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        icons[key] = image
        return image
    }
}

// MARK: - 화면

struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    let onPick: (ClipboardItem) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                list
                footer
            }
            .frame(width: ClipboardPanelController.listWidth)

            if model.previewOpen {
                Divider()
                ClipboardPreview(item: model.selected, model: model)
                    .frame(width: ClipboardPanelController.previewWidth)
            }
        }
        .frame(height: ClipboardPanelController.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("클립보드", "Clipboard")).font(.headline)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("검색어를 입력하세요…", "Search…"), text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            Button {
                model.setPreview(!model.previewOpen)
            } label: {
                Image(systemName: model.previewOpen ? "sidebar.right" : "sidebar.trailing")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help(model.previewOpen ? L("미리보기 접기 (⌘←)", "Hide preview (⌘←)") : L("미리보기 펼치기 (⌘→)", "Show preview (⌘→)"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    let items = model.filtered
                    let highlighted = model.highlightedID
                    if items.isEmpty {
                        Text(model.query.isEmpty ? L("기록이 없습니다", "No history yet") : L("검색 결과가 없습니다", "No results"))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(item: item, index: index, isSelected: item.id == highlighted, model: model)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onPick(item) }
                            .onTapGesture { model.selectedID = item.id }
                    }
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(L("↩ 복사 · ⇧↩ 바로 붙여넣기 · ⌘P 고정 · ⌘⌫ 삭제", "↩ copy · ⇧↩ paste · ⌘P pin · ⌘⌫ delete"))
                Spacer()
                Text(L("\(model.filtered.count)개", "\(model.filtered.count) items"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let model: ClipboardPanelModel

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppInfo.icon(for: item.sourceApp))
                .resizable()
                .frame(width: 16, height: 16)
                .opacity(0.9)
            if item.isImage {
                Group {
                    if let thumb = model.thumbnail(item) {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).aspectRatio(1.6, contentMode: .fit)
                    }
                }
                .frame(maxWidth: 200, maxHeight: 44, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                Spacer(minLength: 0)
            } else if let files = item.files, !files.isEmpty {
                Image(systemName: files.count == 1 ? "doc" : "doc.on.doc").foregroundStyle(isSelected ? .white : .secondary)
                Text(fileSummary(files))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            } else {
                Text(oneLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            if item.isPinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(isSelected ? .white : .orange)
            }
            if index < 10 {
                Text("⌘\(index == 9 ? 0 : index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, item.isImage ? 4 : 6)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func fileSummary(_ files: [String]) -> String {
        let first = (files[0] as NSString).lastPathComponent
        return files.count == 1 ? first : L("\(first) 외 \(files.count - 1)개", "\(first) and \(files.count - 1) more")
    }

    /// 줄바꿈을 ⏎로 보여 한 줄에 요약 (Maccy처럼). 한 줄에 보이는 건 몇십 자라 앞 300자만 배치한다.
    private var oneLine: String {
        let collapsed = String(item.text.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return collapsed.isEmpty ? L("(공백)", "(whitespace)") : collapsed
    }
}

private struct ClipboardPreview: View {
    let item: ClipboardItem?
    let model: ClipboardPanelModel

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                if item.isImage {
                    ScrollView {
                        if let image = model.thumbnail(item, maxPixel: 1400) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        } else {
                            ProgressView().padding(40)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    let preview = model.previewText(item)
                    // SwiftUI Text는 긴 글(특히 고정폭 글꼴의 한글)을 한 번에 배치해 수 초씩 멈춘다 →
                    // 보이는 부분만 배치하는 시스템 텍스트 뷰로
                    PreviewTextView(id: item.id, text: preview.text)
                    if preview.truncated {
                        Label(L("미리보기는 앞 200 KB까지만 보여 줍니다. 복사하면 전체가 들어갑니다.", "Preview shows the first 200 KB only. Copying includes everything."), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                Divider()
                // 하단: 어느 앱에서, 언제
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(nsImage: AppInfo.icon(for: item.sourceApp)).resizable().frame(width: 16, height: 16)
                        Text(AppInfo.name(for: item.sourceApp)).font(.callout.weight(.semibold))
                        Spacer()
                        if item.isPinned { Label(L("고정됨", "Pinned"), systemImage: "pin.fill").font(.caption).foregroundStyle(.orange) }
                    }
                    Text(L("복사한 시간: \(item.copiedAt.formatted(date: .abbreviated, time: .standard))", "Copied: \(item.copiedAt.formatted(date: .abbreviated, time: .standard))"))
                    Text(detail(item))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
            }
        } else {
            Text(L("선택한 항목이 없습니다", "Nothing selected"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detail(_ item: ClipboardItem) -> String {
        if item.isImage {
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.imageBytes ?? 0), countStyle: .file)
            return L("이미지 \(item.imageWidth ?? 0) × \(item.imageHeight ?? 0) px · \(size)", "Image \(item.imageWidth ?? 0) × \(item.imageHeight ?? 0) px · \(size)")
        }
        if let files = item.files, !files.isEmpty {
            let missing = files.filter { !FileManager.default.fileExists(atPath: $0) }.count
            return L("파일 \(files.count)개 (경로만 기록)", "\(files.count) file(s) (paths only)")
                + (missing > 0 ? L(" · \(missing)개는 지금 없음", " · \(missing) no longer exist") : "")
        }
        if item.isLargeText {
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.textBytes ?? 0), countStyle: .file)
            return L("긴 텍스트 \(size) (전체 보관)", "Long text \(size) (stored in full)")
        }
        let lines = item.text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return L("\(item.text.count)자 · \(lines)줄", "\(item.text.count) chars · \(lines) lines")
    }
}

/// 읽기 전용·선택 가능한 시스템 텍스트 뷰. 화면에 보이는 부분만 배치해 MB 단위 로그도 바로 뜬다.
private struct PreviewTextView: NSViewRepresentable {
    let id: UUID
    let text: String

    final class Coordinator {
        var shownID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.isRichText = false
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.textColor = .labelColor
            textView.textContainerInset = NSSize(width: 10, height: 10)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // 같은 항목이면 다시 넣지 않는다 (큰 문자열 비교·재배치 방지)
        guard context.coordinator.shownID != id, let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.shownID = id
        textView.string = text
        textView.scroll(.zero)
    }
}
