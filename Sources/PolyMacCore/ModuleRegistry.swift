import Foundation

/// 모듈 타입을 등록해두고, 활성화될 때 처음으로 인스턴스를 만든다 (lazy).
@MainActor
public final class ModuleRegistry {
    private var types: [String: any PolyMacModule.Type] = [:]
    private var active: [String: any PolyMacModule] = [:]

    public init() {}

    public func register(_ type: any PolyMacModule.Type) {
        types[type.descriptor.id] = type
    }

    public var registeredIDs: [String] { types.keys.sorted() }

    public func isActive(_ id: String) -> Bool { active[id] != nil }

    public func activate(_ id: String) throws {
        guard active[id] == nil, let type = types[id] else { return }
        let context = ModuleContext(moduleID: id)
        let module = type.init(context: context)
        do {
            try module.activate()
        } catch {
            context.logger.error("activate failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        active[id] = module
        context.logger.info("activated")
    }

    /// 비활성화하면 인스턴스를 버려 메모리를 반환한다.
    public func deactivate(_ id: String) {
        guard let module = active.removeValue(forKey: id) else { return }
        module.deactivate()
        ModuleContext(moduleID: id).logger.info("deactivated")
    }
}
