import Foundation
import Testing
@testable import FinderModule

@Test func resolveKeepsSavedInstalledEditor() {
    let app = EditorApp.resolve(saved: "dev.zed.Zed", isInstalled: { _ in true }, name: { _ in nil })
    #expect(app.bundleID == "dev.zed.Zed")
    #expect(app.opensFolders)
}

@Test func resolveFallsBackToFirstInstalledKnownEditor() {
    let installed: Set<String> = ["com.sublimetext.4", "com.apple.TextEdit"]
    // 저장된 앱이 지워졌으면
    let app = EditorApp.resolve(saved: "com.microsoft.VSCode", isInstalled: { installed.contains($0) }, name: { _ in nil })
    #expect(app.bundleID == "com.sublimetext.4")
    // 아무것도 없으면 텍스트 편집기
    let none = EditorApp.resolve(saved: nil, isInstalled: { _ in false }, name: { _ in nil })
    #expect(none.bundleID == "com.apple.TextEdit")
    #expect(!none.opensFolders)
}

@Test func resolveAcceptsAppChosenByUser() {
    let app = EditorApp.resolve(saved: "com.jetbrains.intellij", isInstalled: { _ in true }, name: { _ in "IntelliJ IDEA" })
    #expect(app.name == "IntelliJ IDEA")
    #expect(app.opensFolders)
}

@Test func splitDropsFoldersOnlyForFileEditors() {
    let file = URL(fileURLWithPath: "/tmp/a.txt"), folder = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let isFolder: (URL) -> Bool = { $0.hasDirectoryPath }
    let textEdit = EditorApp.known.first { $0.bundleID == "com.apple.TextEdit" }!
    #expect(textEdit.split([file, folder], isFolder: isFolder) == ([file], [folder]))
    let code = EditorApp.known[0]
    #expect(code.split([file, folder], isFolder: isFolder) == ([file, folder], []))
}

@Test func knownEditorsHaveUniqueIDs() {
    #expect(Set(EditorApp.known.map(\.bundleID)).count == EditorApp.known.count)
}
