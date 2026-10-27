import PolyMacCore

@MainActor
public final class ClipboardModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "clipboard",
        displayName: "클립보드 히스토리",
        permissions: []
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        // TODO: changeCount 감시(0.5s) → ClipboardPrivacy 확인 → 저장, ⇧⌘V 팝업 (docs/CONCEPT.md 4.7)
    }

    public func deactivate() {}
}
