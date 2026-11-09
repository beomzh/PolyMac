import AppKit
import Carbon.HIToolbox
import Testing
@testable import ClipboardModule

/// 기록(모듈)이 고정 상태의 주인이고 패널은 받은 목록을 보여 준다. ⌘P가 두 쪽을 따로 뒤집으면 패널이 거꾸로 보인다.
@MainActor @Suite struct ClipboardPinTests {
    /// 모듈 흉내: 고정을 뒤집고 바뀐 목록을 패널에 넣는다 (ClipboardModule.togglePin → didChange → panel.update)
    @MainActor final class History {
        var items: [ClipboardItem]
        let panel = ClipboardPanelController()
        init(_ texts: [String]) {
            items = texts.map { ClipboardItem(text: $0, sourceApp: nil) }
            let directory = FileManager.default.temporaryDirectory
            panel.prepare(items: items, imageDirectory: directory, textDirectory: directory, store: nil)
        }
        var callbacks: ClipboardPanelController.Callbacks {
            .init(choose: { _, _, _ in }, togglePin: { [unowned self] id in
                guard let i = items.firstIndex(where: { $0.id == id }) else { return }
                items[i].isPinned.toggle()
                panel.update(items: items)
            }, delete: { _ in }, pin: { _ in })
        }
        func copy(_ text: String) {
            items.insert(ClipboardItem(text: text, sourceApp: nil), at: 0)
            panel.update(items: items)
        }
        func pressPin(on text: String) {
            let model = panel.model!
            model.selectedID = model.items.first { $0.text == text }!.id
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                         context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false,
                                         keyCode: UInt16(kVK_ANSI_P))!
            #expect(panel.handle(event, callbacks))
        }
        func pinnedInHistory() -> Set<String> { Set(items.filter(\.isPinned).map(\.text)) }
        func pinnedOnScreen() -> Set<String> { Set(panel.model!.filtered.filter(\.isPinned).map(\.text)) }
    }

    @Test func pinningSeveralShowsAndKeepsThemAll() {
        let history = History(["a", "b", "c"])
        history.pressPin(on: "a")
        history.pressPin(on: "b")
        #expect(history.pinnedInHistory() == ["a", "b"])
        #expect(history.pinnedOnScreen() == ["a", "b"])
        history.copy("d")
        #expect(history.pinnedOnScreen() == ["a", "b"])
    }

    @Test func pressingAgainUnpins() {
        let history = History(["a", "b"])
        history.pressPin(on: "a")
        history.pressPin(on: "a")
        #expect(history.pinnedInHistory().isEmpty)
        #expect(history.pinnedOnScreen().isEmpty)
        history.copy("c")
        #expect(history.pinnedOnScreen().isEmpty)
    }
}
