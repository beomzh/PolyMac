import Foundation
import Testing
@testable import UninstallerCore

/// 가짜 Library 폴더를 만들어 탐색 규칙을 확인한다.
private func makeFakeLibrary(_ entries: [String: [String]]) throws -> (URL, [LeftoverScanner.Location]) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("polymac-uninstall-\(UUID().uuidString)")
    var locations: [LeftoverScanner.Location] = []
    let kinds: [String: LeftoverItem.Kind] = [
        "Application Support": .appSupport, "Caches": .caches, "Preferences": .preferences,
        "Group Containers": .groupContainers, "LaunchAgents": .launchAgent, "Logs": .logs,
    ]
    for (dir, names) in entries {
        let url = root.appendingPathComponent(dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in names { FileManager.default.createFile(atPath: url.appendingPathComponent(name).path, contents: Data()) }
        locations.append(.init(url, kinds[dir]!))
    }
    return (root, locations)
}

private let app = AppBundleInfo(url: URL(fileURLWithPath: "/Applications/Foo Bar.app"), bundleID: "com.foo.FooBar", name: "Foo Bar", teamID: "ABCDE12345")

@Test func findsExactLikelyAndGuessedLeftovers() throws {
    let (root, locations) = try makeFakeLibrary([
        "Preferences": ["com.foo.FooBar.plist", "com.foo.FooBar.helper.plist", "com.other.App.plist"],
        "Caches": ["com.foo.FooBar", "FooBar"],
        "Application Support": ["Foo Bar", "FooBarHelper Data", "Unrelated"],
        "Group Containers": ["ABCDE12345.com.foo.shared", "ZZZZZ.com.other"],
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    let items = LeftoverScanner.scan(app: app, locations: locations)
    func confidence(_ name: String) -> LeftoverItem.Confidence? { items.first { $0.url.lastPathComponent == name }?.confidence }

    #expect(items.first?.kind == .app)
    #expect(confidence("com.foo.FooBar.plist") == .exact)
    #expect(confidence("com.foo.FooBar.helper.plist") == .exact)
    #expect(confidence("com.foo.FooBar") == .exact)
    #expect(confidence("ABCDE12345.com.foo.shared") == .likely)
    #expect(confidence("Foo Bar") == .likely)         // 이름과 같음
    #expect(confidence("FooBar") == .likely)
    #expect(confidence("FooBarHelper Data") == .guessed) // 이름이 들어감 → 기본 선택 안 함
    #expect(confidence("com.other.App.plist") == nil)
    #expect(confidence("ZZZZZ.com.other") == nil)
    #expect(confidence("Unrelated") == nil)
}

@Test func launchAgentPointingIntoAppIsLikely() throws {
    let (root, locations) = try makeFakeLibrary(["LaunchAgents": []])
    defer { try? FileManager.default.removeItem(at: root) }
    let plist: NSDictionary = ["Label": "com.vendor.updater", "ProgramArguments": ["/Applications/Foo Bar.app/Contents/MacOS/updater", "--daemon"]]
    plist.write(to: locations[0].directory.appendingPathComponent("com.vendor.updater.plist"), atomically: true)

    let items = LeftoverScanner.scan(app: app, locations: locations)
    #expect(items.contains { $0.kind == .launchAgent && $0.confidence == .likely })
}

@Test func findsOrphansOfDeletedApps() throws {
    let (root, locations) = try makeFakeLibrary([
        "Preferences": ["com.gone.OldApp.plist", "com.apple.finder.plist", "com.foo.FooBar.plist", "com.foo.Updater.plist", "loginwindow.plist"],
        "Caches": ["com.gone.OldApp"],
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    let groups = LeftoverScanner.orphans(locations: locations, isInstalled: { _ in false }, installedIDs: ["com.foo.FooBar"])
    let ids = groups.map(\.bundleID)
    #expect(ids.contains("com.gone.OldApp"))
    #expect(groups.first { $0.bundleID == "com.gone.OldApp" }?.items.count == 2)
    #expect(!ids.contains("com.apple.finder"))   // macOS 기본은 제외
    #expect(!ids.contains("com.foo.FooBar"))     // 설치된 앱
    #expect(!ids.contains("loginwindow"))        // 역도메인 형태 아님
    // 같은 회사 앱이 설치돼 있으면 추정으로 낮춤
    #expect(groups.first { $0.bundleID == "com.foo.Updater" }?.items.first?.confidence == .guessed)
}

@Test func teamPrefixedNamesAreExact() throws {
    let (root, locations) = try makeFakeLibrary(["Caches": ["QWERTY1234.com.foo.FooBar", "QWERTY1234.other"]])
    defer { try? FileManager.default.removeItem(at: root) }
    let items = LeftoverScanner.scan(app: app, locations: locations)
    #expect(items.first { $0.url.lastPathComponent == "QWERTY1234.com.foo.FooBar" }?.confidence == .exact)
    #expect(!items.contains { $0.url.lastPathComponent == "QWERTY1234.other" })
}

@Test func orphanRulesSkipInstalledParentsAndLiveServices() throws {
    let (root, locations) = try makeFakeLibrary([
        "Preferences": ["com.vendor.App.ShipIt.A63A9676-B16D-5374-BDA1-21A96D85C95E.plist"],
        "LaunchAgents": [],
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let agents = locations.first { $0.kind == .launchAgent }!.directory
    // 프로그램이 아직 있는 서비스 (앱 없이 설치된 보안 프로그램 등) → 건드리지 않음
    (["Label": "com.bank.security", "Program": "/bin/ls"] as NSDictionary).write(to: agents.appendingPathComponent("com.bank.security.plist"), atomically: true)
    // 프로그램이 지워진 서비스 → 흔적
    (["Label": "com.gone.agent", "Program": "/Applications/Gone.app/Contents/MacOS/agent"] as NSDictionary).write(to: agents.appendingPathComponent("com.gone.agent.plist"), atomically: true)
    // 살아 있는 서비스가 실행하는 도우미 파일 → 흔적 아님
    let prefs = locations.first { $0.kind == .preferences }!.directory
    let helper = prefs.appendingPathComponent("com.live.helper")
    FileManager.default.createFile(atPath: helper.path, contents: Data())
    (["Label": "com.live.service", "Program": helper.path] as NSDictionary).write(to: agents.appendingPathComponent("com.live.service.plist"), atomically: true)

    let groups = LeftoverScanner.orphans(locations: locations, isInstalled: { $0 == "com.vendor.App" })
    let ids = groups.map(\.bundleID)
    #expect(!ids.contains { $0.hasPrefix("com.vendor.App") }) // 설치된 앱의 업데이터(ShipIt)
    #expect(!ids.contains("com.bank.security"))
    #expect(!ids.contains("com.live.helper"))
    #expect(!ids.contains("com.live.service"))
    #expect(groups.first { $0.bundleID == "com.gone.agent" }?.items.first?.reason.contains("지워진") == true)
}

@Test func systemAppsAreProtected() {
    #expect(AppBundleInfo(url: URL(fileURLWithPath: "/System/Applications/Notes.app"), bundleID: "com.apple.Notes", name: "Notes").isSystemApp)
    #expect(!app.isSystemApp)
}
