import Foundation
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
    public let displayName: String
    public let permissions: [Permission]
    public let residency: Residency

    public init(id: String, displayName: String, permissions: [Permission], residency: Residency = .inProcess) {
        self.id = id
        self.displayName = displayName
        self.permissions = permissions
        self.residency = residency
    }
}

/// 모듈에 주입되는 공유 서비스. 모듈끼리는 직접 참조하지 않고 이것을 통해 연결된다.
public struct ModuleContext: Sendable {
    public let logger: Logger

    public init(moduleID: String) {
        self.logger = Logger(subsystem: "dev.polymac", category: moduleID)
    }
}

@MainActor
public protocol PolyMacModule: AnyObject {
    static var descriptor: ModuleDescriptor { get }
    init(context: ModuleContext)
    func activate() throws
    func deactivate()
}
