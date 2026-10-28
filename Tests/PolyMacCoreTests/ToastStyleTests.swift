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

@Test func positionDurationAndEnabled() throws {
    let defaults = try #require(UserDefaults(suiteName: "toast-style-test-\(UUID().uuidString)"))
    var style = ToastStyle()
    style.isEnabled = false
    style.position = .topRight
    style.seconds = 4
    style.save(to: defaults)
    let loaded = ToastStyle.load(from: defaults)
    #expect(!loaded.isEnabled && loaded.position == .topRight && loaded.seconds == 4)
    #expect(loaded.duration(for: 2) == 4)   // 보통 알림
    #expect(loaded.duration(for: 5) == 10)  // 오래 뜨는 안내도 같은 비율
    defaults.set("nowhere", forKey: "toast.position")
    #expect(ToastStyle.load(from: defaults).position == .bottomCenter)
}

@Test func positionsStayOnScreen() {
    let area = CGRect(x: 0, y: 80, width: 1440, height: 795)
    let size = CGSize(width: 300, height: 60)
    for p in ToastPosition.allCases {
        let frame = CGRect(origin: p.origin(for: size, in: area), size: size)
        #expect(area.contains(frame), "\(p)")
    }
    #expect(ToastPosition.topRight.origin(for: size, in: area) == CGPoint(x: 1116, y: 791))
}

@Test func latinKeyIgnoresInputSource() throws {
    // 한글 2벌식에서 R 자리는 "ㄱ" — 단축키는 자판 위치로 판단해야 한다
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                              context: nil, characters: "ㄱ", charactersIgnoringModifiers: "ㄱ", isARepeat: false, keyCode: 15))
    #expect(event.latinKey == "r")
    let other = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                              context: nil, characters: "/", charactersIgnoringModifiers: "/", isARepeat: false, keyCode: 44))
    #expect(other.latinKey == "/")
}
