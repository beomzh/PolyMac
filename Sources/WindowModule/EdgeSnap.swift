import AppKit
import ApplicationServices
import PolyMacCore

/// 창을 끌어 화면 가장자리에 대면 놓을 자리를 미리 보여주고, 놓으면 그 자리로 맞춘다.
/// 왼쪽·오른쪽 가장자리 = 절반, 위 = 최대화, 네 모서리 = 4분의 1.
public enum SnapZone: Equatable, Sendable {
    case left, right, maximize, topLeft, topRight, bottomLeft, bottomRight

    /// 이만큼 가장자리에 가까우면 스냅 (pt)
    static let edge: CGFloat = 4
    /// 모서리로 보는 범위 (pt)
    static let corner: CGFloat = 60

    /// point·screen 모두 Cocoa 좌표 (왼쪽 아래 원점)
    public static func at(_ point: CGPoint, screen: CGRect) -> SnapZone? {
        let nearLeft = point.x <= screen.minX + edge, nearRight = point.x >= screen.maxX - edge - 1
        let nearTop = point.y >= screen.maxY - edge - 1, nearBottom = point.y <= screen.minY + edge
        let inTop = point.y >= screen.maxY - corner, inBottom = point.y <= screen.minY + corner
        let inLeft = point.x <= screen.minX + corner, inRight = point.x >= screen.maxX - corner
        if (nearLeft && inTop) || (nearTop && inLeft) { return .topLeft }
        if (nearRight && inTop) || (nearTop && inRight) { return .topRight }
        if (nearLeft && inBottom) || (nearBottom && inLeft) { return .bottomLeft }
        if (nearRight && inBottom) || (nearBottom && inRight) { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .maximize }
        return nil
    }

    /// 놓을 자리 (Cocoa 좌표). area는 메뉴 막대·Dock을 뺀 visibleFrame.
    public func frame(in area: CGRect) -> CGRect {
        let w = area.width / 2, h = area.height / 2
        switch self {
        case .left: return CGRect(x: area.minX, y: area.minY, width: w, height: area.height)
        case .right: return CGRect(x: area.midX, y: area.minY, width: w, height: area.height)
        case .maximize: return area
        case .topLeft: return CGRect(x: area.minX, y: area.midY, width: w, height: h)
        case .topRight: return CGRect(x: area.midX, y: area.midY, width: w, height: h)
        case .bottomLeft: return CGRect(x: area.minX, y: area.minY, width: w, height: h)
        case .bottomRight: return CGRect(x: area.midX, y: area.minY, width: w, height: h)
        }
    }
}

/// 마우스 전역 감시로 창 끌기를 알아챈다. 마우스 위치만 보고, 키 입력은 보지 않는다.
@MainActor
final class EdgeSnapper {
    private var monitors: [Any] = []
    private var window: AXUIElement?
    private var startFrame: CGRect?
    private var moving = false
    private var lastCheck = Date.distantPast
    private var zone: SnapZone?
    private var screen: NSScreen?
    private lazy var preview = SnapPreview()
    /// 스냅하기 직전 창과 위치 (되돌리기용)
    var onSnap: ((AXUIElement, CGRect, CGRect) -> Void)?

    func start() {
        guard monitors.isEmpty else { return }
        let events: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] _ in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() }),
        ]
        for (mask, handler) in events {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
                MainActor.assumeIsolated { handler(event) }
            }) { monitors.append(m) }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func reset() {
        window = nil; startFrame = nil; moving = false; zone = nil; screen = nil
        preview.orderOut(nil)
    }

    private func mouseDown() {
        reset()
    }

    private func mouseDragged() {
        guard Permissions.accessibility else { return }
        if !moving {
            // AX 호출은 비싸므로 끄는 동안 0.05초에 한 번만 확인
            let now = Date()
            guard now.timeIntervalSince(lastCheck) > 0.05 else { return }
            lastCheck = now
            if window == nil {
                // 누른 뒤 첫 끌기: 이때 앞에 온 창과 그 위치를 기억
                guard let w = AX.focusedWindow(), let f = AX.frame(of: w) else { return }
                window = w; startFrame = f
                return
            }
            guard let w = window, let start = startFrame, let now = AX.frame(of: w) else { return }
            // 위치만 바뀌고 크기는 그대로면 창을 옮기는 중 (크기 조절·글자 선택은 제외)
            let moved = abs(now.minX - start.minX) + abs(now.minY - start.minY) > 2
            let sameSize = abs(now.width - start.width) < 1 && abs(now.height - start.height) < 1
            guard moved && sameSize else { return }
            moving = true
        }
        let point = NSEvent.mouseLocation
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
        let newZone = SnapZone.at(point, screen: s.frame)
        guard newZone != zone || s != screen else { return }
        zone = newZone; screen = s
        if let newZone {
            preview.show(newZone.frame(in: s.visibleFrame))
        } else {
            preview.orderOut(nil)
        }
    }

    private func mouseUp() {
        defer { reset() }
        guard moving, let zone, let screen, let window, let from = AX.frame(of: window) else { return }
        let target = AX.axRect(fromCocoa: zone.frame(in: screen.visibleFrame))
        // 창 서버가 끌기를 마친 뒤에 옮긴다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            AX.setFrame(window, target)
            self?.onSnap?(window, from, target)
        }
    }
}

/// 놓을 자리를 보여주는 반투명 상자. 클릭은 통과한다.
@MainActor
private final class SnapPreview: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let box = NSVisualEffectView()
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 2
        box.layer?.borderColor = NSColor.controlAccentColor.cgColor
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        contentView = box
    }

    func show(_ frame: CGRect) {
        setFrame(frame.insetBy(dx: 6, dy: 6), display: true)
        orderFrontRegardless()
    }
}
