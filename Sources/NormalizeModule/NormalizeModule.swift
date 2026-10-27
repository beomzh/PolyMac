import PolyMacCore

@MainActor
public final class NormalizeModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "normalize",
        displayName: "한글 자소분리 해결",
        permissions: [.filesAndFolders]
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        // TODO: 감시 폴더 FSEvents 스트림 시작 → HangulNormalizer.renameToNFC (docs/CONCEPT.md 4.8)
    }

    public func deactivate() {}
}
