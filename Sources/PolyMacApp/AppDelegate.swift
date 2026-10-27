import AppKit
import CaptureModule
import ClipboardModule
import FinderModule
import NormalizeModule
import OCRModule
import OrganizeModule
import PolyMacCore
import ServiceManagement
import UninstallerModule
import WindowModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let registry = ModuleRegistry()
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
        watchAccessibilityChanges()
        logger.info("launched \(self.version, privacy: .public) accessibility=\(Permissions.accessibility)")
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
        Toast.show("손쉬운 사용 권한이 확인되었습니다\n창 분할 · Finder ⌘X · 자동 붙여넣기를 사용할 수 있습니다", duration: 3)
    }

    // MARK: - 모듈 on/off

    private func defaultsKey(_ id: String) -> String { "module.\(id).enabled" }

    private func isEnabled(_ descriptor: ModuleDescriptor) -> Bool {
        UserDefaults.standard.object(forKey: defaultsKey(descriptor.id)) as? Bool ?? descriptor.enabledByDefault
    }

    private func activate(_ descriptor: ModuleDescriptor) {
        do {
            try registry.activate(descriptor.id)
        } catch {
            Toast.show("\(descriptor.displayName)을(를) 켜지 못했습니다\n\(error.localizedDescription)", duration: 5)
        }
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let descriptor = registry.descriptors.first(where: { $0.id == id })
        else { return }
        if registry.isActive(id) {
            registry.deactivate(id)
            UserDefaults.standard.set(false, forKey: defaultsKey(id))
            Toast.show("\(descriptor.displayName) 끔")
        } else {
            UserDefaults.standard.set(true, forKey: defaultsKey(id))
            activate(descriptor)
            if registry.isActive(id) { Toast.show("\(descriptor.displayName) 켬") }
        }
    }

    // MARK: - 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        accessibilityChanged() // 권한 변경 알림이 오지 않는 경우가 있어 메뉴를 열 때도 확인
        menu.removeAllItems()
        menu.addItem(disabled("PolyMac \(version)"))
        menu.addItem(.separator())

        menu.addItem(disabled("기능 켜기 / 끄기"))
        for descriptor in registry.descriptors {
            let item = NSMenuItem(title: descriptor.displayName, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = descriptor.id
            item.state = registry.isActive(descriptor.id) ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        let tools = registry.descriptors.compactMap { d -> NSMenuItem? in
            guard let items = registry.module(d.id)?.menuItems(), !items.isEmpty else { return nil }
            let parent = NSMenuItem(title: d.displayName, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            items.forEach(sub.addItem)
            parent.submenu = sub
            return parent
        }
        if !tools.isEmpty {
            menu.addItem(.separator())
            tools.forEach(menu.addItem)
        }

        menu.addItem(.separator())
        menu.addItem(submenu("단축키", hotkeyItems()))
        menu.addItem(submenu("권한", permissionItems()))

        let login = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let data = NSMenuItem(title: "데이터 폴더 열기", action: #selector(openDataFolder), keyEquivalent: "")
        data.target = self
        menu.addItem(data)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "PolyMac 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func hotkeyItems() -> [NSMenuItem] {
        let settings = NSMenuItem(title: "단축키 변경…", action: #selector(openShortcutSettings), keyEquivalent: ",")
        settings.target = self
        var items: [NSMenuItem] = [settings, .separator()]
        let list = HotkeyCenter.shared.registrations
        if list.isEmpty { items.append(disabled("등록된 단축키 없음")) }
        for r in list {
            let combo = r.combo?.display ?? "—"
            let mark = r.combo == nil ? "   (사용 안 함)" : (r.isRegistered ? (r.note.map { "   (\($0))" } ?? "") : "   ⚠️ 다른 앱이 사용 중")
            items.append(disabled("\(combo)\t\(r.name)\(mark)"))
        }
        if list.contains(where: { $0.combo != nil && !$0.isRegistered }) {
            items.append(.separator())
            items.append(disabled("⚠️ 표시된 단축키는 다른 앱(Spectacle 등)을 끄거나 단축키를 바꾸면 동작합니다"))
        }
        return items
    }

    @objc private func openShortcutSettings() {
        let names = Dictionary(uniqueKeysWithValues: registry.descriptors.map { ($0.id, $0.displayName) })
        ShortcutSettingsWindow.shared.show(moduleNames: names)
    }

    private func permissionItems() -> [NSMenuItem] {
        func row(_ title: String, granted: Bool, _ permission: Permission) -> NSMenuItem {
            let item = NSMenuItem(title: "\(granted ? "✅" : "⚠️") \(title)\(granted ? "" : " — 클릭해서 설정 열기")", action: #selector(openPermission(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = permission.rawValue
            return item
        }
        return [
            row("손쉬운 사용 (창 분할, ⌘X, 자동 붙여넣기)", granted: Permissions.accessibility, .accessibility),
            row("화면 녹음 (캡처, OCR)", granted: Permissions.screenRecording, .screenRecording),
            row("자동화 › Finder (터미널 열기, 경로 복사)", granted: true, .automationFinder),
            row("파일 및 폴더 (자소분리, 자동 정리)", granted: true, .filesAndFolders),
            .separator(),
            disabled("자동화·파일 권한은 처음 사용할 때 macOS가 직접 묻습니다"),
        ]
    }

    @objc private func openPermission(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let permission = Permission(rawValue: raw) else { return }
        switch permission {
        case .accessibility where !Permissions.accessibility: Permissions.requestAccessibility()
        case .screenRecording where !Permissions.screenRecording: Permissions.requestScreenRecording()
        default: break
        }
        Permissions.openSettings(for: permission)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                Toast.show("로그인 시 자동 실행 끔")
            } else {
                try SMAppService.mainApp.register()
                Toast.show("로그인 시 자동 실행 켬")
            }
        } catch {
            Toast.show("로그인 항목 변경 실패: \(error.localizedDescription)", duration: 4)
        }
    }

    @objc private func openDataFolder() {
        NSWorkspace.shared.open(AppPaths.dataDirectory)
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
