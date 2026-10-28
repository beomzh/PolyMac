import Foundation
import PolyMacL10n

/// 삭제할 앱 정보
public struct AppBundleInfo: Sendable, Hashable, Identifiable {
    public let url: URL
    public let bundleID: String
    public let name: String
    public let version: String?
    /// 코드 서명의 개발사 팀 ID (같은 개발사의 공유 데이터 판정용)
    public let teamID: String?
    /// 실행 파일 이름 (충돌 기록이 이 이름으로 남는다)
    public let executableName: String?

    public var id: String { url.path }

    public init(url: URL, bundleID: String, name: String, version: String? = nil, teamID: String? = nil, executableName: String? = nil) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.teamID = teamID
        self.executableName = executableName
    }

    /// macOS 기본 앱 — 지우면 시스템이 망가질 수 있어 대상에서 뺀다
    public var isSystemApp: Bool {
        bundleID.hasPrefix("com.apple.") || url.path.hasPrefix("/System/")
    }
}

/// 앱을 지울 때 함께 지울 후보 하나. UI 없는 순수 데이터라 테스트와 화면에서 같이 쓴다.
public struct LeftoverItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case app, appSupport, caches, preferences, containers, groupContainers
        case savedState, webData, logs, crashReports, tempFiles, plugins
        case launchAgent, launchDaemon, privilegedHelper, receipt, sharedData, relocated, other

        public var title: String {
            switch self {
            case .app: return L("앱 본체", "App")
            case .appSupport: return L("앱 데이터", "App data")
            case .caches: return L("캐시", "Caches")
            case .preferences: return L("설정", "Preferences")
            case .containers: return L("샌드박스 데이터", "Sandbox data")
            case .groupContainers: return L("공유 데이터", "Shared data")
            case .savedState: return L("창 상태 기록", "Saved window state")
            case .webData: return L("웹 데이터 (쿠키·저장소)", "Web data (cookies, storage)")
            case .logs: return L("로그", "Logs")
            case .crashReports: return L("충돌 기록", "Crash reports")
            case .tempFiles: return L("임시 파일", "Temporary files")
            case .plugins: return L("플러그인·확장", "Plug-ins & extensions")
            case .launchAgent: return L("백그라운드 항목 (로그인 시 실행)", "Background items (run at login)")
            case .launchDaemon: return L("시스템 백그라운드 서비스", "System background services")
            case .privilegedHelper: return L("관리자 권한 도우미", "Privileged helpers")
            case .receipt: return L("설치 기록", "Install receipts")
            case .sharedData: return L("공유 폴더 데이터", "Shared folder data")
            case .relocated: return L("macOS 업데이트가 옮겨 둔 항목", "Items relocated by macOS updates")
            case .other: return L("기타", "Other")
            }
        }

        /// 지워도 되는지 판단을 돕는 한 줄 설명
        public var explanation: String {
            switch self {
            case .app: return L("앱 자체입니다.", "The app itself.")
            case .appSupport: return L("문서·DB·플러그인 등 앱이 만든 데이터. 다시 설치해도 이어서 쓰려면 남겨 두세요.", "Documents, databases, plug-ins the app created. Keep them if you plan to reinstall and continue.")
            case .caches: return L("다시 만들 수 있는 임시 파일. 지워도 안전합니다.", "Temporary files that can be recreated. Safe to remove.")
            case .preferences: return L("앱 설정 값. 지우면 다시 설치했을 때 처음 상태로 시작합니다.", "App settings. Without them a reinstall starts fresh.")
            case .containers: return L("App Store·샌드박스 앱의 데이터 전체가 들어 있는 폴더입니다.", "Holds all data of an App Store / sandboxed app.")
            case .groupContainers: return L("같은 개발사 앱끼리 나눠 쓰는 데이터. 그 개발사의 다른 앱을 쓰고 있다면 확인하세요.", "Data shared between apps of one developer. Check first if you use their other apps.")
            case .savedState: return L("다음 실행 때 창을 복원하기 위한 기록. 지워도 안전합니다.", "Used to restore windows on next launch. Safe to remove.")
            case .webData: return L("앱 안 웹 화면의 쿠키·로컬 저장소. 지우면 로그인이 풀립니다.", "Cookies and local storage of the app's web views. Removing them signs you out.")
            case .logs: return L("기록 파일. 지워도 안전합니다.", "Log files. Safe to remove.")
            case .crashReports: return L("앱이 비정상 종료될 때 남긴 보고서. 지워도 안전합니다.", "Reports from when the app crashed. Safe to remove.")
            case .tempFiles: return L("macOS가 앱별로 따로 두는 숨은 캐시·임시 폴더(/var/folders). 지워도 안전합니다.", "Hidden per-app cache and temp folders macOS keeps (/var/folders). Safe to remove.")
            case .plugins: return L("다른 앱(오디오 프로그램, Quick Look, Spotlight, 시스템 설정 등)에 꽂혀 동작하는 구성요소입니다.", "Components that plug into other apps (audio apps, Quick Look, Spotlight, System Settings, …).")
            case .launchAgent: return L("로그인할 때마다 몰래 실행되는 항목. 앱을 지웠다면 함께 지우는 게 좋습니다.", "Runs silently at every login. Best removed along with the app.")
            case .launchDaemon: return L("시스템 시작 때 관리자 권한으로 실행되는 서비스. 지울 때 암호가 필요합니다.", "A service that runs with admin rights at startup. Removing it needs your password.")
            case .privilegedHelper: return L("앱이 설치한 관리자 권한 도우미 프로그램. 지울 때 암호가 필요합니다.", "A privileged helper the app installed. Removing it needs your password.")
            case .receipt: return L("설치 프로그램(pkg)이 남긴 설치 기록. 지울 때 암호가 필요합니다.", "An install receipt left by a pkg installer. Removing it needs your password.")
            case .sharedData: return L("모든 사용자 계정이 함께 쓰는 /Users/Shared에 앱(주로 게임 런처)이 남긴 데이터.", "Data an app (often a game launcher) left in /Users/Shared, which all accounts share.")
            case .relocated: return L("macOS 업데이트 때 새 시스템과 맞지 않아 옮겨 둔 예전 설정 파일. 안을 확인했다면 지워도 됩니다. 암호가 필요합니다.", "Old configuration files a macOS update set aside as incompatible. Remove after checking inside. Needs your password.")
            case .other: return ""
            }
        }
    }

    /// 이 항목을 해당 앱의 것으로 판단한 근거
    public enum Confidence: Int, Sendable, Comparable {
        case guessed = 0
        case likely = 1
        case exact = 2

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .exact: return L("확실", "Certain")
            case .likely: return L("유력", "Likely")
            case .guessed: return L("추정", "Possible")
            }
        }

        /// 확실·유력은 기본 선택, 추정은 사용자가 확인하고 고르게
        public var selectedByDefault: Bool { self != .guessed }
    }

    public let url: URL
    public let kind: Kind
    public let confidence: Confidence
    /// 사람이 읽는 판단 근거 ("앱 ID와 정확히 일치" 등)
    public let reason: String
    public let requiresAdmin: Bool

    public var id: String { url.path }

    public init(url: URL, kind: Kind, confidence: Confidence, reason: String, requiresAdmin: Bool = false) {
        self.url = url
        self.kind = kind
        self.confidence = confidence
        self.reason = reason
        self.requiresAdmin = requiresAdmin
    }
}
