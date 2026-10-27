import AppKit
import ImageIO
import PolyMacCore
import SwiftUI

/// 클립보드 히스토리 창. 평소에는 좁은 목록만, ⌘→ 또는 오른쪽 위 버튼으로 미리보기 패널을 옆으로 펼친다.
/// 앞에 있던 앱의 포커스를 빼앗지 않는 패널이라 ⇧↩︎로 그 앱에 바로 붙여넣을 수 있다. 닫으면 창을 버린다.
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

    func show(items: [ClipboardItem], imageDirectory: URL, textDirectory: URL, callbacks: Callbacks) {
        guard panel == nil else { close(); return }
        let model = ClipboardPanelModel(items: items, imageDirectory: imageDirectory, textDirectory: textDirectory,
                                        previewOpen: UserDefaults.standard.bool(forKey: Self.previewKey))
        self.model = model

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
            panel.setFrame(frame, display: true, animate: true)
        }
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(model: model, onPick: { [weak self] item in
            self?.close()
            callbacks.choose(item, false)
        }))

        // 마우스가 있는 화면, 마우스 근처 (Maccy처럼)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let x = min(max(mouse.x - Self.listWidth / 2, visible.minX + 8), visible.maxX - width(model.previewOpen) - 8)
            let y = min(max(mouse.y - Self.height + 40, visible.minY + 8), visible.maxY - Self.height - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // 목록 이동·복사 키는 검색창이 먹기 전에 가로챈다
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 로컬 모니터는 메인 스레드에서 불린다
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.handle(event, callbacks)
            }
            return handled ? nil : event
        }
        // 다른 곳을 클릭하면 닫는다
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func width(_ previewOpen: Bool) -> CGFloat {
        Self.listWidth + (previewOpen ? Self.previewWidth : 0)
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    func update(items: [ClipboardItem]) {
        model?.items = items
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
        guard cmd, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
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
    @Published var items: [ClipboardItem]
    @Published var query = "" {
        didSet { selectedID = filtered.first?.id }
    }
    @Published var selectedID: UUID?
    @Published private(set) var previewOpen: Bool
    var onTogglePreview: (() -> Void)?

    let imageDirectory: URL
    let textDirectory: URL
    private var thumbnails: [String: NSImage] = [:]

    init(items: [ClipboardItem], imageDirectory: URL, textDirectory: URL, previewOpen: Bool) {
        self.items = items
        self.imageDirectory = imageDirectory
        self.textDirectory = textDirectory
        self.previewOpen = previewOpen
        self.selectedID = nil
        self.selectedID = ordered.first?.id
    }

    func setPreview(_ open: Bool) {
        guard open != previewOpen else { return }
        previewOpen = open
        onTogglePreview?()
    }

    /// 고정 항목 먼저, 그다음 최근 순
    private var ordered: [ClipboardItem] { items.filter(\.isPinned) + items.filter { !$0.isPinned } }

    /// 띄어쓰기로 나눈 단어가 모두 들어 있는 항목 (대소문자·한글 정규화 무시). "이미지"로 이미지만 찾기.
    var filtered: [ClipboardItem] {
        let words = query.precomposedStringWithCanonicalMapping.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ordered }
        return ordered.filter { item in
            let text = (item.isImage ? "이미지 image" : item.text).precomposedStringWithCanonicalMapping.lowercased()
            let app = AppInfo.name(for: item.sourceApp).lowercased()
            return words.allSatisfy { text.contains($0) || app.contains($0) }
        }
    }

    var selected: ClipboardItem? { filtered.first { $0.id == selectedID } ?? filtered.first }

    func move(_ delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? 0
        selectedID = list[min(max(index + delta, 0), list.count - 1)].id
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isPinned.toggle()
    }

    func remove(_ id: UUID) {
        let list = filtered
        let index = list.firstIndex { $0.id == id } ?? 0
        items.removeAll { $0.id == id }
        let rest = filtered
        selectedID = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
    }

    /// 큰 텍스트 미리보기: 화면이 버벅이지 않게 앞 200 KB까지만 읽는다 (복사는 전체)
    static let previewLimit = 200 * 1024

    func previewText(_ item: ClipboardItem) -> (text: String, truncated: Bool) {
        guard let file = item.textFile,
              let handle = try? FileHandle(forReadingFrom: textDirectory.appendingPathComponent(file))
        else { return (item.text, false) }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.previewLimit)) ?? Data()
        // 잘린 끝의 깨진 UTF-8 바이트는 버린다
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\u{FFFD}") { text.removeLast() }
        return (text, (item.textBytes ?? 0) > Self.previewLimit)
    }

    /// 목록·미리보기용 축소 이미지 (원본 전체를 메모리에 올리지 않게 ImageIO 축소본, 창을 닫으면 버림)
    func thumbnail(_ item: ClipboardItem, maxPixel: Int = 240) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        let key = "\(file)@\(maxPixel)"
        if let cached = thumbnails[key] { return cached }
        let url = imageDirectory.appendingPathComponent(file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[key] = image
        return image
    }
}

/// 번들 ID → 앱 이름·아이콘 (한 번 찾으면 기억)
@MainActor
enum AppInfo {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static func name(for bundleID: String?) -> String {
        guard let bundleID else { return "알 수 없음" }
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
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(height: ClipboardPanelController.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.18), value: model.previewOpen)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("클립보드").font(.headline)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("검색어를 입력하세요…", text: $model.query)
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
            .help(model.previewOpen ? "미리보기 접기 (⌘←)" : "미리보기 펼치기 (⌘→)")
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
                    if items.isEmpty {
                        Text(model.query.isEmpty ? "기록이 없습니다" : "검색 결과가 없습니다")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(item: item, index: index, isSelected: item.id == model.selected?.id, model: model)
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
                Text("↩ 복사 · ⇧↩ 바로 붙여넣기 · ⌘P 고정 · ⌘⌫ 삭제")
                Spacer()
                Text("\(model.filtered.count)개")
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
            if item.isImage, let thumb = model.thumbnail(item) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 44, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Spacer(minLength: 0)
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

    /// 줄바꿈을 ⏎로 보여 한 줄에 요약 (Maccy처럼)
    private var oneLine: String {
        let collapsed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return collapsed.isEmpty ? "(공백)" : collapsed
    }
}

private struct ClipboardPreview: View {
    let item: ClipboardItem?
    let model: ClipboardPanelModel

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    if item.isImage, let image = model.thumbnail(item, maxPixel: 1400) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    } else {
                        let preview = model.previewText(item)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preview.text)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if preview.truncated {
                                Label("미리보기는 앞 200 KB까지만 보여 줍니다. 복사하면 전체가 들어갑니다.", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                    }
                }
                Divider()
                // 하단: 어느 앱에서, 언제
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(nsImage: AppInfo.icon(for: item.sourceApp)).resizable().frame(width: 16, height: 16)
                        Text(AppInfo.name(for: item.sourceApp)).font(.callout.weight(.semibold))
                        Spacer()
                        if item.isPinned { Label("고정됨", systemImage: "pin.fill").font(.caption).foregroundStyle(.orange) }
                    }
                    Text("복사한 시간: \(item.copiedAt.formatted(date: .abbreviated, time: .standard))")
                    Text(detail(item))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
            }
        } else {
            Text("선택한 항목이 없습니다")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detail(_ item: ClipboardItem) -> String {
        if item.isImage {
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.imageBytes ?? 0), countStyle: .file)
            return "이미지 \(item.imageWidth ?? 0) × \(item.imageHeight ?? 0) px · \(size)"
        }
        if item.isLargeText {
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.textBytes ?? 0), countStyle: .file)
            return "긴 텍스트 \(size) (전체 보관)"
        }
        return "\(item.text.count)자 · \(item.text.components(separatedBy: .newlines).count)줄"
    }
}
