import Testing
@testable import PolyMacCore

@MainActor
private final class FakeModule: PolyMacModule {
    static let descriptor = ModuleDescriptor(id: "fake", displayName: ("가짜", "Fake"), summary: ("", ""), permissions: [])
    static var activations = 0
    init(context: ModuleContext) {}
    func activate() throws { Self.activations += 1 }
    func deactivate() {}
}

@MainActor
@Test func lazyActivationAndRelease() throws {
    let registry = ModuleRegistry()
    registry.register(FakeModule.self)
    #expect(!registry.isActive("fake"))

    try registry.activate("fake")
    try registry.activate("fake") // 중복 활성화는 무시
    #expect(registry.isActive("fake"))
    #expect(FakeModule.activations == 1)

    registry.deactivate("fake")
    #expect(!registry.isActive("fake"))
}

@Test func displayNameFollowsLanguage() {
    defer { L10n.override = nil }
    L10n.override = .en
    #expect(FakeModule.descriptor.displayName == "Fake")
    L10n.override = .ko
    #expect(FakeModule.descriptor.displayName == "가짜")
}
