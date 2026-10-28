import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PolyMacCore

@MainActor
public final class WindowModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "window",
        displayName: ("창 분할", "Window Layout"),
        summary: ("단축키로 창을 반쪽·사분면·최대화로 배치", "Snap windows to halves, quarters or full screen with shortcuts"),
        permissions: [.accessibility]
    )

    enum Action: String {
        case left, right, top, bottom, maximize, center, nextDisplay, previousDisplay, undo
    }

    private let context: ModuleContext
    private var lastAction: (action: Action, step: Int, time: Date)?
    private var undoFrame: (window: AXUIElement, frame: CGRect)?
    private var snapper: EdgeSnapper?

    /// 가장자리 끌기 스냅. macOS 15부터 시스템에도 같은 기능이 있어 겹치지 않게 기본은 끔.
    private static let edgeSnapKey = "window.edgeSnap"
    private var edgeSnapOn: Bool { UserDefaults.standard.bool(forKey: Self.edgeSnapKey) }

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        if !Permissions.accessibility { Permissions.requestAccessibility() }

        // Spectacle 기본 단축키와 같게
        let bindings: [(KeyCombo, Action, String)] = [
            (KeyCombo(kVK_LeftArrow, [.option, .command]), .left, L("왼쪽 절반 (반복: ⅓ → ⅔)", "Left half (repeat: ⅓ → ⅔)")),
            (KeyCombo(kVK_RightArrow, [.option, .command]), .right, L("오른쪽 절반 (반복: ⅓ → ⅔)", "Right half (repeat: ⅓ → ⅔)")),
            (KeyCombo(kVK_UpArrow, [.option, .command]), .top, L("위쪽 절반", "Top half")),
            (KeyCombo(kVK_DownArrow, [.option, .command]), .bottom, L("아래쪽 절반", "Bottom half")),
            (KeyCombo(kVK_ANSI_F, [.option, .command]), .maximize, L("최대화", "Maximize")),
            (KeyCombo(kVK_ANSI_C, [.option, .command]), .center, L("가운데", "Center")),
            (KeyCombo(kVK_RightArrow, [.control, .option, .command]), .nextDisplay, L("다음 디스플레이", "Next display")),
            (KeyCombo(kVK_LeftArrow, [.control, .option, .command]), .previousDisplay, L("이전 디스플레이", "Previous display")),
            (KeyCombo(kVK_ANSI_Z, [.option, .command]), .undo, L("창 위치 되돌리기", "Undo window move")),
        ]
        for (combo, action, name) in bindings {
            context.hotkey(action.rawValue, combo, name) { [weak self] in self?.perform(action) }
        }
        if edgeSnapOn { startSnapper() }
    }

    public func deactivate() {
        context.unregisterHotkeys()
        snapper?.stop()
        snapper = nil
    }

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: L("가장자리로 끌어 배치", "Snap by Dragging to Edges"), action: #selector(toggleEdgeSnap), keyEquivalent: "")
        item.target = self
        item.state = edgeSnapOn ? .on : .off
        item.toolTip = L("창을 화면 왼쪽·오른쪽 끝으로 끌면 절반, 위쪽은 최대화, 모서리는 4분의 1. 시스템 설정 › 데스크탑 및 Dock의 같은 기능과 함께 켜면 둘 다 반응합니다.",
                         "Drag a window to the left/right edge for a half, the top for full screen, a corner for a quarter. If the same option in System Settings › Desktop & Dock is also on, both will react.")
        return [item]
    }

    @objc private func toggleEdgeSnap() {
        let on = !edgeSnapOn
        UserDefaults.standard.set(on, forKey: Self.edgeSnapKey)
        if on {
            startSnapper()
            context.toast(L("가장자리 끌기 배치를 켰습니다. 시스템의 같은 기능(데스크탑 및 Dock › 창 타일링)은 꺼 두세요.",
                            "Edge snapping is on. Turn off the system's own tiling (Desktop & Dock › Windows) to avoid both reacting."))
        } else {
            snapper?.stop()
            snapper = nil
            context.toast(L("가장자리 끌기 배치를 껐습니다", "Edge snapping is off"))
        }
    }

    private func startSnapper() {
        if !Permissions.accessibility { Permissions.requestAccessibility() }
        let snapper = EdgeSnapper()
        snapper.onSnap = { [weak self] window, from, _ in self?.undoFrame = (window, from) }
        snapper.start()
        self.snapper = snapper
    }

    private func perform(_ action: Action) {
        guard Permissions.accessibility else {
            context.toast(L("창 분할: 손쉬운 사용 권한이 필요합니다", "Window Layout needs Accessibility permission"))
            Permissions.requestAccessibility()
            return
        }
        guard let window = AX.focusedWindow(), let frame = AX.frame(of: window) else {
            context.logger.info("no focused window")
            return
        }

        if action == .undo {
            if let undo = undoFrame, CFEqual(undo.window, window) {
                AX.setFrame(window, undo.frame)
                undoFrame = (window, frame)
            }
            return
        }

        let now = Date()
        var step = 0
        if let last = lastAction, last.action == action, now.timeIntervalSince(last.time) < 1.5 {
            step = (last.step + 1) % 3
        }
        lastAction = (action, step, now)

        let screen = AX.screen(containing: frame)
        guard let target = targetFrame(for: action, step: step, current: frame, screen: screen) else { return }
        undoFrame = (window, frame)
        AX.setFrame(window, target)
    }

    private func targetFrame(for action: Action, step: Int, current: CGRect, screen: NSScreen) -> CGRect? {
        let area = AX.axRect(fromCocoa: screen.visibleFrame)
        let fraction: CGFloat = [1.0 / 2, 1.0 / 3, 2.0 / 3][step]
        switch action {
        case .left:
            return CGRect(x: area.minX, y: area.minY, width: area.width * fraction, height: area.height)
        case .right:
            let w = area.width * fraction
            return CGRect(x: area.maxX - w, y: area.minY, width: w, height: area.height)
        case .top:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .bottom:
            return CGRect(x: area.minX, y: area.minY + area.height / 2, width: area.width, height: area.height / 2)
        case .maximize:
            return area
        case .center:
            let w = min(current.width, area.width), h = min(current.height, area.height)
            return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return nil }
            let offset = action == .nextDisplay ? 1 : -1
            let targetScreen = screens[(index + offset + screens.count) % screens.count]
            let to = AX.axRect(fromCocoa: targetScreen.visibleFrame)
            // 같은 상대 위치·비율로 옮긴다
            let rx = (current.minX - area.minX) / area.width, ry = (current.minY - area.minY) / area.height
            let rw = min(current.width / area.width, 1), rh = min(current.height / area.height, 1)
            return CGRect(x: to.minX + rx * to.width, y: to.minY + ry * to.height, width: rw * to.width, height: rh * to.height)
        case .undo:
            return nil
        }
    }
}

/// Accessibility API 래퍼. AX 좌표는 주 화면 왼쪽 위가 원점, Cocoa는 왼쪽 아래가 원점.
@MainActor
enum AX {
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // 앞의 앱이 응답하지 않을 때 기본 6초 동안 PolyMac이 멈추지 않게
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef
        else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// 크기 → 위치 → 크기 순서. 화면 경계 때문에 첫 크기 변경이 잘리는 앱을 보정한다.
    static func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        var size = rect.size, point = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func axRect(fromCocoa r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func screen(containing axFrame: CGRect) -> NSScreen {
        let center = CGPoint(x: axFrame.midX, y: primaryHeight - axFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
