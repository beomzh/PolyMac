import Testing
@testable import FinderModule

@Test func cutStateFollowsClipboardNumber() {
    // Finder의 복사가 닿으면 번호가 1 늘고 파일이 들어 있다
    #expect(CutHUD.state(cutAt: 10, now: 11, files: 3, elapsed: 0.2) == .ready(3))
    #expect(CutHUD.state(cutAt: 10, now: 10, files: 0, elapsed: 0.5) == .waiting)
    // 3초가 지나도 그대로면 ⌘C가 Finder에 닿지 않았다
    #expect(CutHUD.state(cutAt: 10, now: 10, files: 0, elapsed: 3.5) == .missed)
    // 다른 앱이 덮어쓰면 풀린다
    #expect(CutHUD.state(cutAt: 10, now: 12, files: 3, elapsed: 1) == .replaced)
    #expect(CutHUD.state(cutAt: 10, now: 11, files: 0, elapsed: 1) == .replaced)
}

@Test func cutTitleShowsCount() {
    #expect(CutHUD.title(count: 2).contains("2"))
    #expect(CutHUD.title(count: nil) != CutHUD.title(count: 0))
}
