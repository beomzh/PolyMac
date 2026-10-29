import AppKit
import PolyMacCore
import SwiftUI

/// 권한 탭·시작 안내에 보여 줄 권한 상태
enum PermissionState: Equatable {
    case granted
    case missing
    /// 아직 묻지 않음 — "허용하기"를 누르거나 처음 쓸 때 macOS가 묻는다
    case notAsked
    /// 미리 확인할 수 없음 (파일 및 폴더, 꺼져 있는 Finder)
    case unknown

    init(_ automation: AutomationState) {
        switch automation {
        case .granted: self = .granted
        case .denied: self = .missing
        case .notAsked: self = .notAsked
        case .unavailable: self = .unknown
        }
    }

    /// 지금 이 Mac에서 확인할 수 있는 권한 (자동화는 느릴 수 있어 따로)
    @MainActor static func current() -> [Permission: PermissionState] {
        [
            .accessibility: Permissions.accessibility ? .granted : .missing,
            .screenRecording: Permissions.screenRecording ? .granted : .missing,
            .filesAndFolders: .unknown,
        ]
    }
}

/// 한 번이라도 허용됐던 권한을 기억한다. 나중에 꺼져 있으면 업데이트로 서명이 바뀌었거나
/// 시스템 설정에서 꺼진 것이라 사용자에게 알린다 (설정 화면에는 켜진 것처럼 보이는 경우가 있다).
@MainActor
enum PermissionMemory {
    /// 서명이 바뀌면 풀리고, 미리 확인할 수 있는 권한
    static let tracked: [Permission] = [.accessibility, .screenRecording]

    private static func key(_ permission: Permission) -> String { "permission.\(permission.rawValue).grantedBefore" }

    static func note(_ states: [Permission: PermissionState]) {
        for p in tracked where states[p] == .granted && !UserDefaults.standard.bool(forKey: key(p)) {
            UserDefaults.standard.set(true, forKey: key(p))
        }
    }

    /// 켜진 기능이 쓰는데, 예전에는 허용됐다가 지금은 꺼진 권한
    static func lost(_ states: [Permission: PermissionState], needed: Set<Permission>) -> [Permission] {
        tracked.filter { needed.contains($0) && states[$0] == .missing && UserDefaults.standard.bool(forKey: key($0)) }
    }

    static func forget() {
        tracked.forEach { UserDefaults.standard.removeObject(forKey: key($0)) }
    }

    /// 다음 실행 때 권한 탭을 바로 연다 (권한 기록을 지우고 다시 실행한 뒤)
    static let openAfterLaunchKey = "permissions.openAfterLaunch"
}

extension Permission {
    var title: String {
        switch self {
        case .accessibility: return L("손쉬운 사용", "Accessibility")
        case .screenRecording: return L("화면 및 시스템 오디오 녹음", "Screen & System Audio Recording")
        case .automationFinder: return L("자동화 › Finder", "Automation › Finder")
        case .filesAndFolders: return L("파일 및 폴더", "Files & Folders")
        case .fullDiskAccess: return L("전체 디스크 접근", "Full Disk Access")
        }
    }

    var detail: String {
        switch self {
        case .accessibility: return L("창 배치, Finder ⌘X, 클립보드 자동 붙여넣기", "Window layout, Finder ⌘X, clipboard auto-paste")
        case .screenRecording: return L("캡처, 텍스트 추출(OCR) — 허용한 뒤 PolyMac을 다시 실행해야 적용됩니다",
                                        "Capture, text recognition (OCR) — takes effect after PolyMac restarts")
        case .automationFinder: return L("터미널 열기, 에디터로 열기, 경로 복사, 앱 삭제(휴지통으로 옮기기)", "Open Terminal or editor, copy path, uninstall (move to Trash)")
        case .filesAndFolders: return L("한글 파일명 정리, 자동 정리 — 처음 폴더를 볼 때 macOS가 묻습니다",
                                        "Korean filename fix, auto-organize — macOS asks the first time a folder is read")
        case .fullDiskAccess: return ""
        }
    }

    /// 권한 탭에 보여 주는 순서
    static let shown: [Permission] = [.accessibility, .screenRecording, .automationFinder, .filesAndFolders]
}

/// 권한 하나의 상태 아이콘
struct PermissionStatusIcon: View {
    let state: PermissionState?

    var body: some View {
        switch state {
        case .granted?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("허용됨", "Allowed"))
        case .missing?:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(L("허용 필요", "Needs permission"))
        case .notAsked?:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary).help(L("아직 묻지 않음", "Not asked yet"))
        case .unknown?, nil:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(L("처음 쓸 때 macOS가 묻습니다", "macOS asks on first use"))
        }
    }
}
