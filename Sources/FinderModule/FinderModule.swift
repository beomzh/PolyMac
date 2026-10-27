import PolyMacCore

@MainActor
public final class FinderModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "finder",
        displayName: "Finder 도구",
        permissions: [.accessibility, .automationFinder]
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
