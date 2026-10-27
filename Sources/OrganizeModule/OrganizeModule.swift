import PolyMacCore

@MainActor
public final class OrganizeModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "organize",
        displayName: "다운로드 폴더 자동 정리",
        permissions: [.filesAndFolders]
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        // TODO: 감시 폴더 FSEvents(Normalize와 공유) → FileFacts 수집 → RuleEngine.plan
        //       → dryRun이면 미리보기 목록, 아니면 실행 + 처리 기록 (docs/CONCEPT.md 4.9)
    }

    public func deactivate() {}
}
