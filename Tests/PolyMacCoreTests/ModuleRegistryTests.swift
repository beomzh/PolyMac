import Testing
@testable import PolyMacCore

@MainActor
private final class FakeModule: PolyMacModule {
    static let descriptor = ModuleDescriptor(id: "fake", displayName: "Fake", permissions: [])
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
