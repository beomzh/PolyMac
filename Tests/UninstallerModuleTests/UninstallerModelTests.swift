import Foundation
import Testing
import UninstallerCore
@testable import UninstallerModule

@MainActor
@Suite struct UninstallerModelTests {
    private func item(_ path: String, _ confidence: LeftoverItem.Confidence = .exact) -> LeftoverItem {
        LeftoverItem(url: URL(fileURLWithPath: path), kind: .caches, confidence: confidence, reason: "test")
    }

    @Test func searchMatchesDecomposedKoreanAndBundleID() {
        let model = UninstallerModel()
        let name = "카카오톡"
        model.apps = [
            AppBundleInfo(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: "com.kakao.KakaoTalkMac", name: name),
            AppBundleInfo(url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari", name: "Safari"),
        ]
        // Finder에서 복사한 이름은 풀어진(NFD) 한글일 수 있다
        model.query = name.decomposedStringWithCanonicalMapping
        #expect(model.filteredApps.map(\.name) == [name])
        model.query = "KAKAOTALK"
        #expect(model.filteredApps.count == 1)
        model.query = ""
        #expect(model.filteredApps.count == 2)
    }

    @Test func groupSelectionTogglesAndReportsPartialState() {
        let model = UninstallerModel()
        let list = [item("/tmp/a"), item("/tmp/b"), item("/tmp/c")]
        #expect(!model.isAllChecked(list) && !model.isPartlyChecked(list))

        model.toggle(list[0])
        #expect(model.isPartlyChecked(list) && !model.isAllChecked(list))

        model.toggleItems(list) // 일부만 골랐으면 전부 고른다
        #expect(model.isAllChecked(list) && !model.isPartlyChecked(list))

        model.toggleItems(list) // 전부 골랐으면 전부 푼다
        #expect(model.checked.isEmpty)
    }

    @Test func emptyGroupIsNeitherCheckedNorPartlyChecked() {
        let model = UninstallerModel()
        #expect(!model.isAllChecked([]) && !model.isPartlyChecked([]))
    }

    @Test func guessedItemsAreNotSelectedByDefault() {
        #expect(LeftoverItem.Confidence.exact.selectedByDefault)
        #expect(LeftoverItem.Confidence.likely.selectedByDefault)
        #expect(!LeftoverItem.Confidence.guessed.selectedByDefault)
    }

    @Test func parsesSpotlightAttributeLine() {
        let line = "/Applications/Foo Bar.app   kMDItemCFBundleIdentifier = com.example.foo   kMDItemDisplayName = Foo Bar.app"
        #expect(UninstallerModel.attribute("kMDItemCFBundleIdentifier", in: line) == "com.example.foo")
        #expect(UninstallerModel.attribute("kMDItemDisplayName", in: line) == "Foo Bar.app")
        #expect(UninstallerModel.attribute("kMDItemVersion", in: line) == nil)
    }

    @Test func sizeAndNewestModificationCoversNestedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("polymac-size-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("old.bin")
        let new = nested.appendingPathComponent("new.bin")
        try Data(count: 10_000).write(to: old)
        try Data(count: 20_000).write(to: new)
        let past = Date(timeIntervalSinceNow: -86_400 * 30)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        let recent = Date(timeIntervalSinceNow: -60)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: new.path)
        // 폴더 자체의 수정 시각도 센다 — 만든 폴더들은 옛 시각으로 돌려 둔다
        for dir in [nested, nested.deletingLastPathComponent(), root] {
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: dir.path)
        }

        let (size, newest) = UninstallerModel.sizeAndNewestModification(root)
        #expect(size >= 30_000)
        #expect(abs((newest ?? .distantPast).timeIntervalSince(recent)) < 2)

        let (fileSize, _) = UninstallerModel.sizeAndNewestModification(old)
        #expect(fileSize >= 10_000)
        let (missing, missingDate) = UninstallerModel.sizeAndNewestModification(root.appendingPathComponent("nope"))
        #expect(missing == 0 && missingDate == nil)
    }

    @Test func readsAppInfoFromBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("polymac-app-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sample Tool.app")
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.sampletool",
            "CFBundleShortVersionString": "2.3.4",
            "CFBundleExecutable": "SampleTool",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let info = try #require(UninstallerModel.info(app))
        #expect(info.bundleID == "com.example.sampletool")
        #expect(info.name == "Sample Tool")
        #expect(info.version == "2.3.4")
        #expect(info.executableName == "SampleTool")
        #expect(info.teamID == nil) // 서명 없음

        #expect(UninstallerModel.info(root.appendingPathComponent("Missing.app")) == nil)
    }
}
