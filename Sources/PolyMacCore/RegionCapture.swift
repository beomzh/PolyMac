import AppKit
import PolyMacL10n
import ScreenCaptureKit
import os

public struct CaptureResult {
    /// 선택 영역의 원본 이미지 (표시 없음)
    public let image: CGImage
    /// 픽셀 / 포인트 비율 (Retina = 2)
    public let scale: CGFloat
    /// 선택한 영역의 화면 좌표 (Cocoa, 왼쪽 아래 원점)
    public let screenRect: NSRect
    /// 캡처 편집에서 그린 표시 (영역 기준 포인트 좌표)
    public var annotations: [Annotation] = []

    /// 표시까지 합친 이미지
    public var compositeImage: CGImage { AnnotationRenderer.composite(image, scale: scale, annotations: annotations) }

    public init(image: CGImage, scale: CGFloat, screenRect: NSRect, annotations: [Annotation] = []) {
        self.image = image
        self.scale = scale
        self.screenRect = screenRect
        self.annotations = annotations
    }
}

/// 캡처 편집 도구 막대에서 고른 마무리 동작
public enum CaptureAction: Sendable {
    case copy, pin, ocr, save
}

/// 모든 화면을 먼저 찍어 정지 화면 위에서 영역을 고르게 한다 (선택 UI가 캡처에 섞이지 않음).
@MainActor
public enum RegionCapture {
    private static let logger = Logger(subsystem: "dev.polymac", category: "capture")

    /// 영역만 고른다. 취소하면 nil.
    public static func selectRegion() async -> CaptureResult? {
        await run(editing: false).map { $0.0 }
    }

    /// 영역을 고른 뒤 도구 막대로 표시를 그리고 마무리 동작(복사·핀·텍스트 추출·저장)을 고른다.
    public static func captureAndEdit() async -> (CaptureResult, CaptureAction)? {
        guard let (result, action) = await run(editing: true), let action else { return nil }
        return (result, action)
    }

    private static func run(editing: Bool) async -> (CaptureResult, CaptureAction?)? {
        guard Permissions.screenRecording else {
            Permissions.requestScreenRecording()
            Toast.show(L("화면 녹음 권한이 필요합니다.\n시스템 설정에서 PolyMac을 허용한 뒤 앱을 다시 실행하세요.", "Screen Recording permission is needed.\nAllow PolyMac in System Settings, then reopen the app."), duration: 4)
            return nil
        }
        let shots: [(NSScreen, CGImage)]
        do {
            shots = try await snapshots()
        } catch {
            logger.error("snapshot failed: \(error.localizedDescription, privacy: .public)")
            Toast.show(L("화면을 캡처하지 못했습니다: \(error.localizedDescription)", "Could not capture the screen: \(error.localizedDescription)"))
            return nil
        }
        guard !shots.isEmpty else { return nil }
        let windows = windowFrames()
        return await withCheckedContinuation { continuation in
            RegionSelector.shared.begin(shots, editing: editing, windowFrames: windows) { continuation.resume(returning: $0) }
        }
    }

    /// 지금 화면에 떠 있는 일반 창들의 위치 (앞에 있는 창부터, Cocoa 좌표). 클릭 한 번으로 창 크기에 맞춰 고르는 데 쓴다.
    /// 창 위치만 읽고 내용은 읽지 않는다.
    private static func windowFrames() -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info -> NSRect? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 40, rect.height >= 40
            else { return nil }
            // CG 창 좌표는 주 화면 왼쪽 위 원점 → Cocoa(왼쪽 아래 원점)로
            return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    private static func snapshots() async throws -> [(NSScreen, CGImage)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value })
            else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append((screen, image))
        }
        return result
    }
}

@MainActor
final class RegionSelector {
    static let shared = RegionSelector()

    typealias Outcome = (CaptureResult, CaptureAction?)

    private var windows: [NSWindow] = []
    private var selectionViews: [SelectionView] = []
    private var completion: ((Outcome?) -> Void)?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var timeout: DispatchWorkItem?
    /// 캡처 전에 쓰던 앱 — 끝나면 포커스를 돌려준다
    private var previousApp: NSRunningApplication?

    func begin(_ shots: [(NSScreen, CGImage)], editing: Bool, windowFrames: [NSRect], completion: @escaping (Outcome?) -> Void) {
        guard windows.isEmpty else { completion(nil); return }
        self.completion = completion
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        for (screen, image) in shots {
            // 앱을 앞으로 가져오지 않아도 키 입력을 받는 패널 — macOS 14부터 백그라운드 앱의 활성화 요청은 거절될 수 있어
            // 일반 창으로는 ⌘A·C·방향키 등이 전달되지 않았다
            let window = SelectorWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)
            let localBounds = NSRect(origin: .zero, size: screen.frame.size)
            let localWindows = windowFrames
                .map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).intersection(localBounds) }
                .filter { $0.width >= 40 && $0.height >= 40 }
            let view = SelectionView(frame: localBounds, image: image, scale: screen.backingScaleFactor,
                                     editing: editing, windowRects: localWindows)
            window.acceptsMouseMovedEvents = true
            let scale = screen.backingScaleFactor
            view.onFinish = { [weak self, weak window] outcome in
                guard let self else { return }
                let origin = window?.frame.origin ?? .zero
                self.finish(outcome.map { o in
                    var result = CaptureResult(image: o.image, scale: scale, screenRect: o.rect.offsetBy(dx: origin.x, dy: origin.y))
                    result.annotations = o.annotations
                    return (result, o.action)
                })
            }
            view.onActivity = { [weak self] in self?.restartTimeout() }
            view.onSelectionStarted = { [weak self, weak view] in
                // 다른 화면에서 이미 고른 영역·도구 막대는 지운다
                self?.selectionViews.filter { $0 !== view }.forEach { $0.reset() }
            }
            let container = NSView(frame: localBounds)
            container.wantsLayer = true
            container.addSubview(CaptureBackgroundView(frame: localBounds, image: image))
            container.addSubview(view)
            window.contentView = container
            window.initialFirstResponder = view
            window.orderFrontRegardless()
            windows.append(window)
            selectionViews.append(view)
        }
        let underMouse = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        underMouse?.makeKeyAndOrderFront(nil)
        if let underMouse, let view = selectionViews.first(where: { $0.window === underMouse }) {
            underMouse.makeFirstResponder(view)
        }
        installSafetyNets()
    }

    /// 전체 화면을 덮는 창이라, 어떤 경우에도 빠져나올 수 있어야 한다 — 화면이 멈춘 것처럼 보이면 안 된다.
    /// - Esc: PolyMac에 포커스가 없어도 동작 (전역 감시)
    /// - 모니터 연결·해제·덮개 닫기 등 화면 구성 변경: 즉시 취소 (오버레이 좌표가 틀어지므로)
    /// - 2분 동안 아무 조작이 없으면 자동 취소
    private func installSafetyNets() {
        let isEscape: (NSEvent) -> Bool = { $0.keyCode == 53 }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard isEscape(event) else { return event }
            MainActor.assumeIsolated { self?.finish(nil) }
            return nil
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard isEscape(event) else { return }
            MainActor.assumeIsolated { self?.finish(nil) }
        }) { monitors.append(global) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.windows.isEmpty else { return }
                self.finish(nil)
                Toast.show(L("화면 구성이 바뀌어 캡처를 취소했습니다", "Capture cancelled because the display setup changed"))
            }
        }
        restartTimeout()
    }

    private func restartTimeout() {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private func finish(_ outcome: Outcome?) {
        guard !windows.isEmpty || completion != nil else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        timeout?.cancel()
        timeout = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        selectionViews.removeAll()
        previousApp?.activate()
        previousApp = nil
        let completion = completion
        self.completion = nil
        completion?(outcome)
    }
}

private final class SelectorWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}
