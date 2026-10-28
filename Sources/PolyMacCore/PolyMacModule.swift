import AppKit
import PolyMacL10n
import os

/// 모듈이 필요로 하는 시스템 권한.
public enum Permission: String, Sendable, CaseIterable {
    case accessibility
    case screenRecording
    case automationFinder
    case filesAndFolders
    case fullDiskAccess
}

/// 모듈이 메모리에 올라가는 방식.
public enum Residency: Sendable {
    /// 앱 프로세스 안에서, 켜져 있을 때만 생성된다.
    case inProcess
    /// 별도 프로세스로, 사용자가 열 때만 실행된다.
    case onDemandProcess(bundleID: String)
}

public struct ModuleDescriptor: Sendable {
    public let id: String
    private let name: (ko: String, en: String)
    private let about: (ko: String, en: String)
    public let permissions: [Permission]
    public let residency: Residency
    /// 사용자가 아직 켜고 끈 적이 없을 때의 기본값
    public let enabledByDefault: Bool

    /// 현재 언어의 이름
    public var displayName: String { L(name.ko, name.en) }
    /// 환경 설정에 보여 줄 한 줄 설명
    public var summary: String { L(about.ko, about.en) }

    public init(
        id: String,
        displayName: (ko: String, en: String),
        summary: (ko: String, en: String),
        permissions: [Permission],
        residency: Residency = .inProcess,
        enabledByDefault: Bool = true
    ) {
        self.id = id
        self.name = displayName
        self.about = summary
        self.permissions = permissions
        self.residency = residency
        self.enabledByDefault = enabledByDefault
    }
}

public struct ModuleError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// 모듈에 주입되는 공유 서비스. 모듈끼리는 직접 참조하지 않고 이것을 통해 연결된다.
@MainActor
public struct ModuleContext {
    public let moduleID: String
    public let logger: Logger

    public init(moduleID: String) {
        self.moduleID = moduleID
        self.logger = Logger(subsystem: "dev.polymac", category: moduleID)
    }

    public var dataDirectory: URL { AppPaths.dataDirectory }

    public func toast(_ message: String, duration: TimeInterval = 2) {
        Toast.show(message, duration: duration)
    }

    /// 이 모듈 소유의 전역 단축키 등록. `id`는 사용자가 바꾼 조합을 저장하는 키라 바꾸지 않는다.
    /// 모듈을 끌 때 `unregisterHotkeys()`로 한 번에 해제한다.
    public func hotkey(_ id: String, _ defaultCombo: KeyCombo, _ name: String, _ handler: @escaping @MainActor () -> Void) {
        HotkeyCenter.shared.register(key: "\(moduleID).\(id)", defaultCombo: defaultCombo, name: name, owner: moduleID, handler: handler)
    }

    /// 전역 등록 없이 조합만 관리하는 단축키 (예: Finder 안에서만 쓰는 잘라내기). 바뀔 때마다 onChange로 알려 준다.
    public func localShortcut(_ id: String, _ defaultCombo: KeyCombo, _ name: String, note: String,
                              _ onChange: @escaping @MainActor (KeyCombo?) -> Void) {
        HotkeyCenter.shared.registerLocal(key: "\(moduleID).\(id)", defaultCombo: defaultCombo, name: name,
                                          owner: moduleID, note: note, onChange: onChange)
    }

    public func unregisterHotkeys() {
        HotkeyCenter.shared.unregister(owner: moduleID)
    }
}

@MainActor
public protocol PolyMacModule: AnyObject {
    static var descriptor: ModuleDescriptor { get }
    init(context: ModuleContext)
    func activate() throws
    func deactivate()
    /// 메뉴바 메뉴에 덧붙일 항목. 모듈이 켜져 있을 때만 표시된다.
    func menuItems() -> [NSMenuItem]
}

public extension PolyMacModule {
    func menuItems() -> [NSMenuItem] { [] }
}
