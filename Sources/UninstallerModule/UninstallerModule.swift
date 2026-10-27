import AppKit
import PolyMacCore
import SwiftUI

@MainActor
public final class UninstallerModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "uninstaller",
        displayName: "앱 완전 삭제",
        permissions: [.automationFinder]
    )

    private let context: ModuleContext
    private let window = UninstallerWindow()

    public init(context: ModuleContext) {
        self.context = context
    }

    /// 상주 작업이 없다 — 메뉴에서 창을 열 때만 일한다
    public func activate() throws {}

    public func deactivate() {
        window.close()
    }

    public func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "앱 삭제 창 열기…", action: #selector(openApps), keyEquivalent: "")
        let orphans = NSMenuItem(title: "이미 지운 앱의 흔적 찾기…", action: #selector(openOrphans), keyEquivalent: "")
        return [open, orphans].map { $0.target = self; return $0 }
    }

    /// 메뉴바 맨 위 "앱 완전 삭제…"에서 부른다
    public func openWindow() { window.show(mode: .apps) }

    @objc private func openApps() { window.show(mode: .apps) }
    @objc private func openOrphans() { window.show(mode: .orphans) }
}

/// 창과 모델은 열 때 만들고 닫을 때 버린다
@MainActor
final class UninstallerWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: UninstallerModel?

    func show(mode: UninstallerModel.Mode) {
        if let window, let model {
            model.mode = mode
            if mode == .orphans { model.scanOrphans() }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = UninstallerModel()
        model.mode = mode
        model.loadApps()
        if mode == .orphans { model.scanOrphans() }
        let window = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "앱 완전 삭제 — PolyMac"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: UninstallerView(model: model))
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        model = nil
    }
}
