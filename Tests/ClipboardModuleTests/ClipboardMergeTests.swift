import Foundation
import Testing
@testable import ClipboardModule

@Test func copiedWhileWaitingGoesOnTopOfSavedHistory() {
    let saved = [ClipboardItem(text: "old 1", sourceApp: nil), ClipboardItem(text: "old 2", sourceApp: nil)]
    let newer = [ClipboardItem(text: "new", sourceApp: nil)]
    #expect(ClipboardItem.merge(newer, onto: saved).map(\.text) == ["new", "old 1", "old 2"])
}

@Test func sameContentKeepsOnlyTheNewerItem() {
    var pinned = ClipboardItem(text: "같은 글", sourceApp: "com.old", isPinned: true)
    pinned.copiedAt = Date(timeIntervalSince1970: 0)
    let saved = [pinned, .files(["/a", "/b"], sourceApp: nil), .image(file: "x.png", width: 1, height: 1, bytes: 1, hash: "h1", sourceApp: nil)]
    let newer = [ClipboardItem(text: "같은 글", sourceApp: "com.new"), .files(["/a", "/b"], sourceApp: nil),
                 .image(file: "y.png", width: 1, height: 1, bytes: 1, hash: "h1", sourceApp: nil)]
    let merged = ClipboardItem.merge(newer, onto: saved)
    #expect(merged.count == 3)
    #expect(merged.first?.sourceApp == "com.new")
}

@Test func differentImagesAndFileListsAreBothKept() {
    let saved = [ClipboardItem.image(file: "x.png", width: 1, height: 1, bytes: 1, hash: "h1", sourceApp: nil), .files(["/a"], sourceApp: nil)]
    let newer = [ClipboardItem.image(file: "y.png", width: 1, height: 1, bytes: 1, hash: "h2", sourceApp: nil), .files(["/a", "/b"], sourceApp: nil)]
    #expect(ClipboardItem.merge(newer, onto: saved).count == 4)
    #expect(ClipboardItem.merge([], onto: saved) == saved)
}
