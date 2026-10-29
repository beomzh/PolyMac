import AppKit
import CaptureModule
import ClipboardModule
import FinderModule
import NormalizeModule
import OCRModule
import OrganizeModule
import PolyMacCore
import UninstallerModule
import WindowModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SettingsHost {
    private let registry = ModuleRegistry()
    private lazy var services = ServicesProvider(registry: registry)
    private var statusItem: NSStatusItem?
    private let logger = Logger(subsystem: "dev.polymac", category: "app")

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "PolyMacVersion") as? String ?? "dev"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let modules: [any PolyMacModule.Type] = [
            WindowModule.self, CaptureModule.self, OCRModule.self, ClipboardModule.self,
            FinderModule.self, NormalizeModule.self, OrganizeModule.self, UninstallerModule.self,
        ]
        modules.forEach(registry.register)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        item.button?.toolTip = "PolyMac"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        for descriptor in registry.descriptors where isEnabled(descriptor) {
            activate(descriptor)
        }
        NSApp.mainMenu = Self.makeMainMenu(target: self)
        // Finder 우클릭 메뉴 (Info.plist NSServices)
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        watchAccessibilityChanges()
        watchSettingsRequests()
        DockPresence.start()
        logger.info("launched \(self.version, privacy: .public) accessibility=\(Permissions.accessibility)")
        showGuidanceAtLaunch()
    }

    /// 처음 실행이면 시작 안내, 권한 기록을 지우고 다시 실행했으면 권한 탭,
    /// 예전에 허용했던 권한이 꺼졌으면(새로 설치해 서명이 바뀐 경우 등) 알림
    private func showGuidanceAtLaunch() {
        let defaults = UserDefaults.standard
        if OnboardingWindow.shouldShowAtLaunch {
            logger.info("first launch: showing welcome guide")
            OnboardingWindow.shared.show(host: self)
        } else if defaults.bool(forKey: PermissionMemory.openAfterLaunchKey) {
            defaults.removeObject(forKey: PermissionMemory.openAfterLaunchKey)
            SettingsWindow.shared.show(host: self, tab: .permissions)
        } else {
            let lost = PermissionMemory.lost(PermissionState.current(), needed: neededPermissions)
            guard !lost.isEmpty else { return }
            logger.notice("permissions granted before are now off: \(lost.map(\.rawValue).joined(separator: ","), privacy: .public)")
            Toast.show(L("예전에 허용했던 권한이 꺼져 있습니다: ", "Permissions you allowed before are off: ") + lost.map(\.title).joined(separator: ", ")
                       + L("\n메뉴 › 권한이 필요합니다…에서 다시 허용하세요", "\nAllow them again from the menu › Permissions needed…"), duration: 6)
        }
    }

    /// 켜진 기능이 쓰는 권한
    private var neededPermissions: Set<Permission> {
        Set(registry.descriptors.filter { registry.isActive($0.id) }.flatMap(\.permissions))
    }

    /// Dock 아이콘을 누르거나, 실행 중에 Spotlight·Finder로 다시 열었을 때 — 열려 있는 창을 앞으로
    /// polymac://… (단축어 등) — 허용 여부와 동작은 URLActions가 판단한다
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(URLActions.handle)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockPresence.bringWindowsForward()
        return false
    }

    /// 앱 아이콘과 같은 다면체 큐브: 윤곽 + 면 경계, 윗면만 채움. 템플릿 이미지라 메뉴바 밝기에 맞춰 색이 바뀐다.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let s: CGFloat = 7.6
            let c = NSPoint(x: 9, y: 8.2) // 앞쪽 모서리
            let u = NSPoint(x: cos(.pi / 6) * s, y: sin(.pi / 6) * s)
            let v = NSPoint(x: -cos(.pi / 6) * s, y: sin(.pi / 6) * s)
            func p(_ dx: CGFloat, _ dy: CGFloat) -> NSPoint { NSPoint(x: c.x + dx, y: c.y + dy) }
            NSColor.black.set()
            let top = NSBezierPath()
            top.move(to: c)
            top.line(to: p(u.x, u.y))
            top.line(to: p(u.x + v.x, u.y + v.y))
            top.line(to: p(v.x, v.y))
            top.close()
            top.fill()
            let outline = NSBezierPath()
            outline.move(to: p(0, -s))
            outline.line(to: p(u.x, u.y - s))
            outline.line(to: p(u.x, u.y))
            outline.line(to: p(u.x + v.x, u.y + v.y))
            outline.line(to: p(v.x, v.y))
            outline.line(to: p(v.x, v.y - s))
            outline.close()
            outline.move(to: c)
            outline.line(to: p(0, -s))
            outline.lineWidth = 1.3
            outline.lineJoinStyle = .round
            outline.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PolyMac"
        return image
    }

    /// 손쉬운 사용 권한이 바뀌면 시스템이 알림을 보낸다. 허용되면 그 권한이 필요한 모듈을 다시 켜서
    /// (이벤트 탭 등) 사용자가 기능을 껐다 켤 필요가 없게 한다.
    /// 모듈이 환경 설정의 특정 탭을 열어 달라고 할 때 (예: 자동 정리 › 규칙 편집…)
    private func watchSettingsRequests() {
        NotificationCenter.default.addObserver(forName: SettingsRequest.open, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                let tab = (note.userInfo?["tab"] as? String).flatMap(SettingsWindow.Tab.init(rawValue:))
                SettingsWindow.shared.show(host: self, tab: tab)
            }
        }
    }

    private func watchAccessibilityChanges() {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            // 알림 직후에는 값이 아직 바뀌지 않았을 수 있어 잠시 뒤 확인
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { self?.accessibilityChanged() }
            }
        }
    }

    private var lastAccessibility = Permissions.accessibility

    private func accessibilityChanged() {
        let now = Permissions.accessibility
        guard now != lastAccessibility else { return }
        lastAccessibility = now
        logger.info("accessibility changed: \(now)")
        guard now else { return }
        for d in registry.descriptors where d.permissions.contains(.accessibility) && registry.isActive(d.id) {
            registry.deactivate(d.id)
            activate(d)
        }
        Toast.show(L("손쉬운 사용 권한이 확인되었습니다\n창 분할 · Finder ⌘X · 자동 붙여넣기를 사용할 수 있습니다",
                     "Accessibility permission granted\nWindow layout, Finder ⌘X and auto-paste are ready"), duration: 3)
    }

    // MARK: - 모듈 on/off

    private func defaultsKey(_ id: String) -> String { "module.\(id).enabled" }

    private func isEnabled(_ descriptor: ModuleDescriptor) -> Bool {
        UserDefaults.standard.object(forKey: defaultsKey(descriptor.id)) as? Bool ?? descriptor.enabledByDefault
    }

    /// 켜지 못하면 이유를 알리고 돌려준다
    @discardableResult
    private func activate(_ descriptor: ModuleDescriptor) -> String? {
        do {
            try registry.activate(descriptor.id)
            return nil
        } catch {
            let reason = L("\(descriptor.displayName)을(를) 켜지 못했습니다", "Could not turn on \(descriptor.displayName)") + "\n" + error.localizedDescription
            Toast.show(reason, duration: 5)
            return reason
        }
    }

    // MARK: - 환경 설정 (SettingsHost)

    var descriptors: [ModuleDescriptor] { registry.descriptors }

    func isActive(_ id: String) -> Bool { registry.isActive(id) }

    func setEnabled(_ id: String, _ on: Bool) -> String? {
        guard let descriptor = registry.descriptors.first(where: { $0.id == id }) else { return nil }
        UserDefaults.standard.set(on, forKey: defaultsKey(id))
        if on {
            return registry.isActive(id) ? nil : activate(descriptor)
        }
        registry.deactivate(id)
        return nil
    }

    /// 켜진 기능을 다시 올려 단축키 이름·메뉴 항목·창을 새 언어로 만든다 (설정은 그대로)
    func languageChanged() {
        for d in registry.descriptors where registry.isActive(d.id) {
            registry.deactivate(d.id)
            activate(d)
        }
        NSApp.mainMenu = Self.makeMainMenu(target: self)
        logger.info("language changed: \(L10n.resolved.rawValue, privacy: .public)")
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(host: self)
    }

    @objc private func openGuide() {
        OnboardingWindow.shared.show(host: self)
    }

    @objc private func openPermissions() {
        SettingsWindow.shared.show(host: self, tab: .permissions)
    }

    // MARK: - 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        accessibilityChanged() // 권한 변경 알림이 오지 않는 경우가 있어 메뉴를 열 때도 확인
        menu.removeAllItems()
        menu.addItem(disabled("PolyMac \(version)"))
        menu.addItem(.separator())

        // 자주 여는 창은 맨 위에 바로
        let uninstall = NSMenuItem(title: L("앱 완전 삭제…", "Uninstall an App…"), action: #selector(openUninstaller), keyEquivalent: "")
        uninstall.target = self
        uninstall.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        uninstall.isEnabled = registry.isActive("uninstaller")
        if !uninstall.isEnabled { uninstall.toolTip = L("환경 설정 › 기능에서 '앱 완전 삭제'를 켜세요", "Turn on 'App Uninstaller' in Settings › Features") }
        menu.addItem(uninstall)

        // 켜진 기능의 도구
        let tools = registry.descriptors.compactMap { d -> NSMenuItem? in
            guard let items = registry.module(d.id)?.menuItems(), !items.isEmpty else { return nil }
            return submenu(d.displayName, items)
        }
        if !tools.isEmpty {
            menu.addItem(.separator())
            tools.forEach(menu.addItem)
        }

        // 켜진 기능에 필요한 권한이 빠졌으면 바로 알 수 있게
        let needed = neededPermissions
        let missing = (needed.contains(.accessibility) && !Permissions.accessibility)
            || (needed.contains(.screenRecording) && !Permissions.screenRecording)
        if missing {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: L("권한이 필요합니다…", "Permissions needed…"), action: #selector(openPermissions), keyEquivalent: "")
            warn.target = self
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let guide = NSMenuItem(title: L("시작 안내…", "Welcome Guide…"), action: #selector(openGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)
        let settings = NSMenuItem(title: L("환경 설정…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: L("PolyMac 종료", "Quit PolyMac"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// 화면에는 안 보이지만 키 조합을 처리하는 기본 메뉴.
    /// 메뉴바 전용 앱이라 이게 없으면 ⌘W(창 닫기)·검색창의 ⌘C/⌘V/⌘A가 동작하지 않는다.
    private static func makeMainMenu(target: AppDelegate) -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        let settings = NSMenuItem(title: L("환경 설정…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = target
        let quit = NSMenuItem(title: L("창 닫기 / PolyMac 종료", "Close Window / Quit PolyMac"), action: #selector(closeWindowOrQuit), keyEquivalent: "q")
        quit.target = target
        submenu("PolyMac", [settings, quit])
        submenu(L("편집", "Edit"), [
            NSMenuItem(title: L("실행 취소", "Undo"), action: NSSelectorFromString("undo:"), keyEquivalent: "z"),
            NSMenuItem(title: L("잘라내기", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: L("복사", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: L("붙여넣기", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: L("모두 선택", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        submenu(L("윈도우", "Window"), [NSMenuItem(title: L("닫기", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")])
        return main
    }

    /// ⌘Q: PolyMac 창(설정·앱 삭제)이 떠 있으면 그 창만 닫고, 없을 때만 종료 — 메뉴바 앱이 실수로 꺼지지 않게
    @objc private func closeWindowOrQuit() {
        if let key = NSApp.keyWindow {
            // 캡처 화면·클립보드 창·핀처럼 닫기 버튼이 없는 창이 앞에 있으면 아무것도 하지 않는다 (실수로 종료 방지)
            if key.styleMask.contains(.closable) { key.performClose(nil) }
            return
        }
        if let window = NSApp.windows.first(where: { $0.isVisible && $0 is ClosableWindow }) {
            window.performClose(nil)
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func openUninstaller() {
        (registry.module("uninstaller") as? UninstallerModule)?.openWindow()
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }
}
