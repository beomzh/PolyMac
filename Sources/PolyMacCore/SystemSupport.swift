import AppKit
import ApplicationServices
import CoreServices
import os

/// 앱 데이터 위치. 다른 사용자가 읽지 못하게 0700으로 만든다 (docs/SECURITY.md 3).
public enum AppPaths {
    public static var dataDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PolyMac", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return url
    }

    /// 파일을 쓰고 권한을 0600으로 맞춘다.
    public static func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 기록 파일이 이 크기를 넘으면 `이름.1.확장자`로 넘기고 새로 시작한다 (이전 것은 하나만 남긴다).
    public static let logRotateBytes = 1_000_000

    /// 한 줄을 덧붙인다 (파일이 없으면 0600으로 만든다).
    public static func appendLine(_ line: String, to url: URL, rotateAt limit: Int = logRotateBytes) {
        rotateIfNeeded(url, limit: limit)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? writePrivate(data, to: url)
        }
    }

    /// `organize-log.txt` → `organize-log.1.txt`. 그전의 `.1`은 지운다.
    static func rotateIfNeeded(_ url: URL, limit: Int) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= limit else { return }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().appendingPathExtension("1")
        let previous = ext.isEmpty ? base : base.appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }
}

/// PolyMac이 직접 만들어 보내는 키 이벤트 표식 (eventSourceUserData). 자기 이벤트 탭이 다시 가로채지 않게 한다.
public enum SyntheticEvent {
    public static let marker: Int64 = 0x504D_4143 // 'PMAC'
}

/// Finder 자동화 권한 상태
public enum AutomationState: Sendable, Equatable {
    case granted
    case denied
    /// 아직 묻지 않음 — 처음 쓸 때(또는 "허용하기")에 macOS가 묻는다
    case notAsked
    /// Finder가 꺼져 있는 등 지금 확인할 수 없음
    case unavailable
}

@MainActor
public enum Permissions {
    public static var accessibility: Bool { AXIsProcessTrusted() }

    private static var lastAccessibilityPrompt: Date?

    /// 시스템 권한 요청 대화상자를 띄운다 (이미 허용됐으면 아무 일도 없음).
    /// 단축키를 누를 때마다 창이 뜨지 않도록 10분에 한 번만.
    public static func requestAccessibility() {
        if let last = lastAccessibilityPrompt, Date().timeIntervalSince(last) < 600 { return }
        lastAccessibilityPrompt = Date()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    public static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Finder 자동화(Apple Events) 허용 상태. 물어보지 않고 확인만 한다 — Finder가 응답할 때까지 잠깐 걸릴 수 있어 메인 스레드 밖에서 부른다.
    public nonisolated static func automationFinder() -> AutomationState {
        determineFinderAutomation(ask: false)
    }

    /// 아직 묻지 않았으면 macOS가 허용 창을 띄운다 (메인 스레드 밖에서). 결과를 돌려준다.
    @discardableResult
    public nonisolated static func requestAutomationFinder() -> AutomationState {
        determineFinderAutomation(ask: true)
    }

    private nonisolated static func determineFinderAutomation(ask: Bool) -> AutomationState {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty { return .unavailable }
        guard let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder").aeDesc else { return .unavailable }
        let status = AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unavailable
        }
    }

    /// 화면 녹음처럼 다시 실행해야 적용되는 권한을 위해 PolyMac을 껐다 켠다.
    public static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 지금 프로세스가 끝난 뒤 같은 앱을 다시 연다 ($0 = 앱 경로, 셸에 문자열로 끼워 넣지 않는다)
        task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            Logger(subsystem: "dev.polymac", category: "permissions").error("relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// PolyMac 자신의 권한 기록만 지운다 (다른 앱은 그대로). 서명이 바뀌어 설정에는 켜져 보이는데 동작하지 않을 때.
    /// 지운 뒤에는 다시 허용해야 한다.
    @discardableResult
    public static func resetRecords() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        var ok = true
        for service in ["Accessibility", "ScreenCapture", "AppleEvents"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", service, bundleID]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                ok = ok && task.terminationStatus == 0
            } catch {
                ok = false
            }
        }
        Logger(subsystem: "dev.polymac", category: "permissions").notice("reset permission records ok=\(ok)")
        return ok
    }

    public static func openSettings(for permission: Permission) {
        let anchor: String
        switch permission {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .automationFinder: anchor = "Privacy_Automation"
        case .filesAndFolders: anchor = "Privacy_FilesAndFolders"
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
/// PolyMac의 어느 기능이 클립보드에 넣었는지. 클립보드 기록이 읽어 출처 태그로 보여 준다.
/// 다른 앱에는 보이지 않는 PolyMac 전용 타입 하나만 더한다 (붙여넣기에는 영향 없음).
public enum PasteboardOrigin: String, Sendable, CaseIterable {
    case ocr, capture, paths, color

    nonisolated public static var type: NSPasteboard.PasteboardType { .init("dev.polymac.origin") }

    public var title: String {
        switch self {
        case .ocr: return L("텍스트 추출", "OCR")
        case .capture: return L("캡처", "Capture")
        case .paths: return L("경로 복사", "Path")
        case .color: return L("색상", "Color")
        }
    }

    public var symbol: String {
        switch self {
        case .ocr: return "text.viewfinder"
        case .capture: return "camera.viewfinder"
        case .paths: return "folder"
        case .color: return "eyedropper"
        }
    }
}

public enum PasteboardWriter {
    /// to: 테스트용 (기본은 시스템 클립보드)
    public static func copy(_ text: String, origin: PasteboardOrigin? = nil, to pb: NSPasteboard = .general) {
        pb.clearContents()
        pb.setString(text, forType: .string)
        mark(pb, origin)
    }

    public static func copy(_ image: CGImage, scale: CGFloat, origin: PasteboardOrigin? = nil) {
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: size)])
        mark(pb, origin)
    }

    private static func mark(_ pb: NSPasteboard, _ origin: PasteboardOrigin?) {
        guard let origin else { return }
        pb.addTypes([PasteboardOrigin.type], owner: nil)
        pb.setString(origin.rawValue, forType: PasteboardOrigin.type)
    }
}

/// FSEvents 폴더 감시. 이벤트가 있을 때만 깨어나므로 유휴 비용이 없다.
public final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private let handler: @MainActor ([String]) -> Void

    public init(paths: [String], latency: CFTimeInterval = 1.0, handler: @escaping @MainActor ([String]) -> Void) {
        self.paths = paths
        self.latency = latency
        self.handler = handler
    }

    deinit { stop() }

    public func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, fsEventsCallback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else {
            Logger(subsystem: "dev.polymac", category: "watcher").error("FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func deliver(_ changed: [String]) {
        MainActor.assumeIsolated { handler(changed) }
    }
}

private func fsEventsCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
    watcher.deliver(paths)
}

public extension NSWindow {
    /// 메뉴바 앱(LSUIElement)의 창을 다른 앱 창보다 앞에 띄운다. macOS 14부터 활성화 요청은 거절될 수 있어
    /// (그러면 창이 다른 앱 뒤에 뜬다) 창 순서는 orderFrontRegardless로 따로 올리고, 메뉴가 닫힌 뒤 한 번 더 시도한다.
    func bringToFront() {
        if self is ClosableWindow { DockPresence.update(showing: self) } // Dock 아이콘을 먼저 띄워야 앞으로 오기도 쉽다
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                NSApp.activate()
                self.makeKeyAndOrderFront(nil)
                self.orderFrontRegardless()
            }
        }
    }
}

/// PolyMac의 일반 창(설정·앱 삭제). Esc로 닫힌다 — 메뉴바 앱이라 창을 닫을 방법이 눈에 안 띄기 쉬워서.
/// 단축키 녹화처럼 Esc를 먼저 쓰는 곳은 이벤트를 가로채므로 여기까지 오지 않는다.
public final class ClosableWindow: NSWindow {
    override public func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// 일반 창(환경 설정·시작 안내·앱 삭제)이 떠 있는 동안만 Dock 아이콘과 ⌘Tab 목록에 나온다.
/// 메뉴바 앱이라 평소에는 숨어 있지만, 창이 다른 앱 뒤로 가면 다시 찾을 방법이 있어야 한다.
@MainActor
public enum DockPresence {
    private static var started = false

    public static func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { if note.object is ClosableWindow { update() } }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let window = note.object as? ClosableWindow { update(closing: window) }
            }
        }
    }

    /// 열려 있는(최소화 포함) 일반 창
    public static var openWindows: [NSWindow] {
        NSApp.windows.filter { $0 is ClosableWindow && ($0.isVisible || $0.isMiniaturized) }
    }

    /// 창이 하나라도 있으면 Dock에 보이고, 마지막 창이 닫히면 다시 메뉴바로만 돌아간다.
    /// showing: 지금 띄우는 중이라 아직 화면에 없는 창, closing: 닫히는 중이라 아직 화면에 있는 창
    public static func update(showing: NSWindow? = nil, closing: NSWindow? = nil) {
        let hasWindow = showing != nil || openWindows.contains { $0 !== closing }
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// Dock 아이콘을 누르거나 Spotlight로 다시 열었을 때 — 열린 창을 모두 앞으로. 창이 없으면 false
    @discardableResult
    public static func bringWindowsForward() -> Bool {
        let windows = openWindows
        guard !windows.isEmpty else { return false }
        NSApp.activate()
        for window in windows {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
        }
        (NSApp.keyWindow.flatMap { w in windows.first { $0 === w } } ?? windows.last)?.makeKeyAndOrderFront(nil)
        return true
    }
}
