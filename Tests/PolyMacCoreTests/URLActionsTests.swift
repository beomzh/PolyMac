import AppKit
import Foundation
import Testing
@testable import PolyMacCore

@MainActor
@Test func parsesPlainAndXCallbackForms() throws {
    let plain = try #require(URLActions.Request(URL(string: "polymac://ocr-table?format=markdown")!))
    #expect(plain.action == "ocr-table")
    #expect(plain.query["format"] == "markdown")
    #expect(plain.success == nil)

    let callback = try #require(URLActions.Request(URL(string: "polymac://x-callback-url/OCR?x-success=shortcuts://x-callback-url/ic-success&x-error=shortcuts://x-callback-url/ic-error")!))
    #expect(callback.action == "ocr")
    #expect(callback.success?.absoluteString == "shortcuts://x-callback-url/ic-success")
    #expect(callback.failure?.absoluteString == "shortcuts://x-callback-url/ic-error")
}

@MainActor
@Test func returnsOnlyToShortcuts() throws {
    let request = try #require(URLActions.Request(URL(string: "polymac://ocr?x-success=https://example.com/steal&x-error=file:///etc/passwd")!))
    #expect(request.success == nil)
    #expect(request.failure == nil)
}

@MainActor
@Test func rejectsOtherSchemesAndOddPaths() {
    #expect(URLActions.Request(URL(string: "http://ocr")!) == nil)
    #expect(URLActions.Request(URL(string: "polymac://")!) == nil)
    #expect(URLActions.Request(URL(string: "polymac://x-callback-url/")!) == nil)
    #expect(URLActions.Request(URL(string: "polymac://x-callback-url/ocr/extra")!) == nil)
}

@MainActor
@Test func htmlCopyKeepsPlainTextAndOrigin() {
    let pb = NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }
    PasteboardWriter.copy("a\tb", html: "<table><tr><td>a</td><td>b</td></tr></table>", origin: .ocr, to: pb)
    #expect(pb.string(forType: .string) == "a\tb")
    #expect(pb.string(forType: .html)?.contains("<td>a</td>") == true)
    #expect(pb.string(forType: PasteboardOrigin.type) == PasteboardOrigin.ocr.rawValue)
}
