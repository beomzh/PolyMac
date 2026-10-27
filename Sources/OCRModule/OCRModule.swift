import PolyMacCore

@MainActor
public final class OCRModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "ocr",
        displayName: "텍스트 추출 (OCR)",
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
