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

    /// 한 줄을 덧붙인다 (파일이 없으면 0600으로 만든다).
    public static func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? writePrivate(data, to: url)
        }
    }
}

/// PolyMac이 직접 만들어 보내는 키 이벤트 표식 (eventSourceUserData). 자기 이벤트 탭이 다시 가로채지 않게 한다.
public enum SyntheticEvent {
    public static let marker: Int64 = 0x504D_4143 // 'PMAC'
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
public enum PasteboardWriter {
    public static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public static func copy(_ image: CGImage, scale: CGFloat) {
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: size)])
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
