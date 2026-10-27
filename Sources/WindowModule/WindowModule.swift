import PolyMacCore

@MainActor
public final class WindowModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "window",
        displayName: "창 분할",
        permissions: [.accessibility]
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        // TODO: 구현 — docs/CONCEPT.md 참고
    }

    public func deactivate() {}
}
