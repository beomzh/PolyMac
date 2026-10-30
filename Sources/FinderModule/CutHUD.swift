import AppKit
import PolyMacCore

/// ⌘X로 잘라 둔 파일이 아직 옮겨지지 않았음을 화면 아래에 작게 띄운다. Finder가 앞에 있을 때만 보인다.
/// 클립보드는 번호(changeCount)와 파일 개수만 보고, 파일 이름은 읽지 않는다.
@MainActor
final class CutHUD {
    static let defaultsKey = "finder.cutHUD"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// 사용자가 취소 버튼을 눌렀거나 다른 앱이 클립보드를 써서 잘라내기가 풀렸을 때
    var onCancel: (() -> Void)?

    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var cutAt: Int?
    private var startedAt = Date()
    private var finderFront = true
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var isPending: Bool { cutAt != nil }

    func begin(changeCount: Int) {
        cutAt = changeCount
        startedAt = Date()
        update(Self.title(count: nil))
        timer?.invalidate()
        // 잘라낸 동안만 돈다: Finder가 클립보드를 채웠는지, 다른 앱이 덮어썼는지
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshVisibility()
    }

    func end() {
        cutAt = nil
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    func setFinderFront(_ front: Bool) {
        finderFront = front
        refreshVisibility()
    }

    enum PollResult: Equatable {
        case waiting, ready(Int), replaced, missed
    }

    /// cutAt: 잘라내기 직전 번호. Finder의 복사가 닿으면 번호가 1 늘고, 그보다 더 늘면 다른 것이 복사됐다.
    nonisolated static func state(cutAt: Int, now: Int, files: Int, elapsed: TimeInterval) -> PollResult {
        if now == cutAt + 1 { return files > 0 ? .ready(files) : .replaced }
        if now > cutAt + 1 { return .replaced }
        // 3초가 지나도 그대로면 ⌘C가 Finder에 닿지 않았다
        return elapsed > 3 ? .missed : .waiting
    }

    nonisolated static func title(count: Int?) -> String {
        guard let count else { return L("✂️ 잘라내는 중…", "✂️ Cutting…") }
        return L("✂️ \(count)개 잘라냄 — 옮길 폴더에서 ⌘V", "✂️ \(count) item(s) cut — press ⌘V in the destination folder")
    }

    private func poll() {
        guard let cutAt else { return }
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.count ?? 0
        switch Self.state(cutAt: cutAt, now: pasteboard.changeCount, files: files, elapsed: Date().timeIntervalSince(startedAt)) {
        case .waiting:
            break
        case .ready(let count):
            update(Self.title(count: count))
        case .replaced, .missed:
            end()
            onCancel?()
        }
    }

    private func refreshVisibility() {
        guard let panel else { return }
        if isPending && finderFront {
            place(panel)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func update(_ text: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        label?.stringValue = text
        place(panel)
    }

    private func place(_ panel: NSPanel) {
        guard let content = panel.contentView else { return }
        let size = content.fittingSize
        let visible = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 24, width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let cancel = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("잘라내기 취소", "Cancel cut")) ?? NSImage(),
                              target: self, action: #selector(cancelTapped))
        cancel.isBordered = false
        cancel.contentTintColor = .secondaryLabelColor
        cancel.toolTip = L("잘라내기 취소 (파일은 그대로, ⌘V는 복사로)", "Cancel the cut (files stay; ⌘V will copy)")
        let stack = NSStackView(views: [label, cancel])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 10)

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        self.label = label
        return panel
    }

    @objc private func cancelTapped() {
        end()
        onCancel?()
    }
}
