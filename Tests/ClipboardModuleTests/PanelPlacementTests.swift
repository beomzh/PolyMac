import AppKit
import Testing
@testable import ClipboardModule

@Suite struct PanelPlacementTests {
    private let size = CGSize(width: 400, height: 520)
    /// Dock이 아래에 81pt, 메뉴 막대가 위에 30pt
    private let withDock = CGRect(x: 0, y: 81, width: 2560, height: 1329)
    /// 왼쪽 보조 화면: Dock도 메뉴 막대도 없다
    private let noDock = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    private func frame(_ cursor: CGPoint, in visible: CGRect) -> CGRect {
        PanelPlacement.frame(size: size, cursor: cursor, listWidth: 400, visible: visible)
    }

    private func isInside(_ frame: CGRect, _ visible: CGRect) -> Bool {
        visible.insetBy(dx: PanelPlacement.margin, dy: PanelPlacement.margin).contains(frame)
    }

    @Test func opensNearTheCursorWhenThereIsRoom() {
        let result = frame(CGPoint(x: 1000, y: 800), in: withDock)
        #expect(result.midX == 1000)
        #expect(result.maxY == 840)
    }

    @Test(arguments: [CGPoint(x: 0, y: 0), CGPoint(x: 2559, y: 0), CGPoint(x: 0, y: 1439), CGPoint(x: 2559, y: 1439)])
    func staysOnScreenAtEveryCornerWithDock(cursor: CGPoint) {
        #expect(isInside(frame(cursor, in: withDock), withDock))
    }

    @Test(arguments: [CGPoint(x: -2560, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: -2560, y: 1439), CGPoint(x: -1, y: 1439)])
    func staysOnScreenAtEveryCornerWithoutDock(cursor: CGPoint) {
        #expect(isInside(frame(cursor, in: noDock), noDock))
    }

    @Test func bottomStaysAboveTheDock() {
        #expect(frame(CGPoint(x: 1000, y: 3), in: withDock).minY == 89)
    }

    @Test func openingPreviewAtTheRightEdgeSlidesLeft() {
        let opened = CGRect(x: 2152, y: 300, width: 781, height: 520)
        let result = PanelPlacement.inside(opened, visible: withDock)
        #expect(result.maxX == 2552)
        #expect(result.minY == 300)
    }

    @Test func tooSmallScreenKeepsTheTopLeft() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 400)
        let result = frame(CGPoint(x: 150, y: 200), in: small)
        #expect(result.minX == 8)
        #expect(result.maxY == 392)
    }
}

@Suite struct ClipboardPanelSizeTests {
    /// 화면 안으로 밀어 넣는 계산이 맞으려면 창이 코드에 적은 크기 그대로여야 한다
    @MainActor @Test(arguments: [false, true])
    func openPanelHasTheExactSize(preview: Bool) {
        let key = "clipboard.previewOpen"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.set(preview, forKey: key)

        let controller = ClipboardPanelController()
        let directory = FileManager.default.temporaryDirectory
        controller.prepare(items: [], imageDirectory: directory, textDirectory: directory, store: nil)
        controller.show(callbacks: .init(choose: { _, _, _ in }, togglePin: { _ in }, delete: { _ in }, pin: { _ in }), pasteOnChoose: false)
        defer { controller.tearDown() }
        controller.panel?.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let expected = ClipboardPanelController.listWidth + (preview ? ClipboardPanelController.previewWidth + ClipboardPanelController.dividerWidth : 0)
        #expect(controller.panel?.frame.size == NSSize(width: expected, height: ClipboardPanelController.height))
        // 제목 표시줄을 숨긴 자리에 놓인 검색창이 클릭을 받아야 한다
        let frameView = controller.panel?.contentView?.superview
        let hit = frameView?.hitTest(NSPoint(x: 200, y: 495))
        #expect(hit?.isDescendant(of: controller.panel!.contentView!) == true)
    }
}
