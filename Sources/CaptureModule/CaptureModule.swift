import PolyMacCore

@MainActor
public final class CaptureModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "capture",
        displayName: "캡처 · 핀 · 마크업",
        permissions: [.screenRecording]
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
