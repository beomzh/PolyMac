import AppKit
import Testing
@testable import PolyMacCore

@Test func hexRoundTrip() throws {
    let color = try #require(ToastStyle.color(hex: "#FF8000"))
    #expect(ToastStyle.hex(color) == "#FF8000")
    let translucent = try #require(ToastStyle.color(hex: "#00000080"))
    #expect(ToastStyle.hex(translucent) == "#00000080")
    #expect(ToastStyle.color(hex: "#12345") == nil)
    #expect(ToastStyle.color(hex: "zzzzzz") == nil)
}

@Test func saveLoadAndClamp() throws {
    let defaults = try #require(UserDefaults(suiteName: "toast-style-test-\(UUID().uuidString)"))
    var style = ToastStyle()
    style.textColor = "#FFFFFF"
    style.backgroundColor = "#202020E6"
    style.fontSize = 99      // 범위 밖 → 28
    style.maxWidth = 500
    style.save(to: defaults)
    let loaded = ToastStyle.load(from: defaults)
    #expect(loaded.textColor == "#FFFFFF")
    #expect(loaded.backgroundColor == "#202020E6")
    #expect(loaded.fontSize == 28)
    #expect(loaded.maxWidth == 500)
    #expect(loaded.padding == ToastStyle().padding)

    // 기본값으로 저장하면 키가 지워져 시스템 색으로 돌아간다
    ToastStyle().save(to: defaults)
    #expect(defaults.object(forKey: "toast.textColor") == nil)
    #expect(defaults.object(forKey: "toast.fontSize") == nil)
    #expect(ToastStyle.load(from: defaults) == ToastStyle())

    defaults.set("not a color", forKey: "toast.backgroundColor")
    #expect(ToastStyle.load(from: defaults).backgroundColor == nil)
}
