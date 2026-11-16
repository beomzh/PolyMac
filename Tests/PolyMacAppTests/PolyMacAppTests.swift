import Foundation
import PolyMacCore
import Testing
@testable import PolyMacApp

@MainActor
@Suite(.serialized) struct PermissionTests {
    @Test func automationStatesMapToPermissionStates() {
        #expect(PermissionState(.granted) == .granted)
        #expect(PermissionState(.denied) == .missing)
        #expect(PermissionState(.notAsked) == .notAsked)
        #expect(PermissionState(.unavailable) == .unknown)
    }

    /// 한 번 허용됐다가 꺼진 권한만, 켜진 기능이 쓸 때만 "풀린 권한"으로 알린다
    @Test func lostPermissionsNeedPriorGrantAndAUser() {
        PermissionMemory.forget()
        defer { PermissionMemory.forget() }
        let needed: Set<Permission> = [.accessibility, .screenRecording]

        // 허용된 적 없음 → 알리지 않는다 (처음 설치한 사람)
        #expect(PermissionMemory.lost([.accessibility: .missing, .screenRecording: .missing], needed: needed).isEmpty)

        PermissionMemory.note([.accessibility: .granted, .screenRecording: .missing])
        let lost = PermissionMemory.lost([.accessibility: .missing, .screenRecording: .missing], needed: needed)
        #expect(lost == [.accessibility])

        // 그 권한을 쓰는 기능이 모두 꺼져 있으면 알리지 않는다
        #expect(PermissionMemory.lost([.accessibility: .missing], needed: [.screenRecording]).isEmpty)
        // 다시 허용되면 알리지 않는다
        #expect(PermissionMemory.lost([.accessibility: .granted], needed: needed).isEmpty)

        PermissionMemory.forget()
        #expect(PermissionMemory.lost([.accessibility: .missing], needed: needed).isEmpty)
    }
}

@MainActor
@Suite struct SettingsTabTests {
    @Test func everyTabHasItsOwnTitleAndIcon() {
        let tabs = SettingsWindow.Tab.allCases
        #expect(Set(tabs.map(\.title)).count == tabs.count)
        #expect(Set(tabs.map(\.symbol)).count == tabs.count)
        #expect(tabs.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }

    /// 모듈이 이름으로 탭을 열어 달라고 한다 (SettingsRequest.open, 예: 자동 정리 › 규칙 편집…)
    @Test func tabsOpenByName() {
        for name in ["organize", "permissions", "clipboard", "window", "ocr", "finder", "normalize", "shortcuts"] {
            #expect(SettingsWindow.Tab(rawValue: name) != nil, "\(name)")
        }
    }
}
