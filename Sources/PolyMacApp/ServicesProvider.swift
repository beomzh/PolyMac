import AppKit
import FinderModule
import NormalizeModule
import PolyMacCore

/// Finder 우클릭 메뉴(macOS 서비스) 받기. Info.plist의 NSServices가 메뉴 이름과 아래 메서드 이름을 잇는다.
/// 기능이 꺼져 있으면 아무것도 하지 않고 켜는 곳을 알려 준다.
@MainActor
final class ServicesProvider: NSObject {
    private let registry: ModuleRegistry

    init(registry: ModuleRegistry) {
        self.registry = registry
    }

    private func files(_ pboard: NSPasteboard) -> [URL] {
        pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func module<T>(_ id: String, as type: T.Type) -> T? {
        if let module = registry.module(id) as? T { return module }
        let name = registry.descriptors.first { $0.id == id }?.displayName ?? id
        Toast.show(L("'\(name)' 기능이 꺼져 있습니다\n환경 설정 › 기능에서 켜세요", "'\(name)' is turned off\nTurn it on in Settings › Features"), duration: 3)
        return nil
    }

    @objc func openTerminal(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        module("finder", as: FinderModule.self)?.openTerminal(at: files(pboard))
    }

    @objc func copyPaths(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        module("finder", as: FinderModule.self)?.copyPaths(of: files(pboard))
    }

    @objc func sendTo(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        module("finder", as: FinderModule.self)?.send(files(pboard))
    }

    @objc func fixNames(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        module("normalize", as: NormalizeModule.self)?.fixNames(files(pboard))
    }

    @objc func windowsZip(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        module("normalize", as: NormalizeModule.self)?.makeWindowsZip(files(pboard))
    }
}
