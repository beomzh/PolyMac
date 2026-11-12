import Testing
@testable import ClipboardModule

@Suite struct ChooseActionTests {
    @Test func defaultCopiesAndShiftPastes() {
        #expect(!ChooseAction.pastes(alternate: false, pasteOnChoose: false))
        #expect(ChooseAction.pastes(alternate: true, pasteOnChoose: false))
    }

    @Test func pasteOnChoosePastesAndShiftCopies() {
        #expect(ChooseAction.pastes(alternate: false, pasteOnChoose: true))
        #expect(!ChooseAction.pastes(alternate: true, pasteOnChoose: true))
    }
}
