import Foundation

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
            case .app: return "앱 본체"
            case .appSupport: return "앱 데이터"
            case .caches: return "캐시"
            case .preferences: return "설정"
            case .containers: return "샌드박스 데이터"
            case .groupContainers: return "공유 데이터"
            case .savedState: return "창 상태 기록"
            case .webData: return "웹 데이터 (쿠키·저장소)"
            case .logs: return "로그"
            case .crashReports: return "충돌 기록"
            case .tempFiles: return "임시 파일"
            case .plugins: return "플러그인·확장"
            case .launchAgent: return "백그라운드 항목 (로그인 시 실행)"
            case .launchDaemon: return "시스템 백그라운드 서비스"
            case .privilegedHelper: return "관리자 권한 도우미"
            case .receipt: return "설치 기록"
            case .sharedData: return "공유 폴더 데이터"
            case .relocated: return "macOS 업데이트가 옮겨 둔 항목"
            case .other: return "기타"
            }
        }

        /// 지워도 되는지 판단을 돕는 한 줄 설명
        public var explanation: String {
            switch self {
            case .app: return "앱 자체입니다."
            case .appSupport: return "문서·DB·플러그인 등 앱이 만든 데이터. 다시 설치해도 이어서 쓰려면 남겨 두세요."
            case .caches: return "다시 만들 수 있는 임시 파일. 지워도 안전합니다."
            case .preferences: return "앱 설정 값. 지우면 다시 설치했을 때 처음 상태로 시작합니다."
            case .containers: return "App Store·샌드박스 앱의 데이터 전체가 들어 있는 폴더입니다."
            case .groupContainers: return "같은 개발사 앱끼리 나눠 쓰는 데이터. 그 개발사의 다른 앱을 쓰고 있다면 확인하세요."
            case .savedState: return "다음 실행 때 창을 복원하기 위한 기록. 지워도 안전합니다."
            case .webData: return "앱 안 웹 화면의 쿠키·로컬 저장소. 지우면 로그인이 풀립니다."
            case .logs: return "기록 파일. 지워도 안전합니다."
            case .crashReports: return "앱이 비정상 종료될 때 남긴 보고서. 지워도 안전합니다."
            case .tempFiles: return "macOS가 앱별로 따로 두는 숨은 캐시·임시 폴더(/var/folders). 지워도 안전합니다."
            case .plugins: return "다른 앱(오디오 프로그램, Quick Look, Spotlight, 시스템 설정 등)에 꽂혀 동작하는 구성요소입니다."
            case .launchAgent: return "로그인할 때마다 몰래 실행되는 항목. 앱을 지웠다면 함께 지우는 게 좋습니다."
            case .launchDaemon: return "시스템 시작 때 관리자 권한으로 실행되는 서비스. 지울 때 암호가 필요합니다."
            case .privilegedHelper: return "앱이 설치한 관리자 권한 도우미 프로그램. 지울 때 암호가 필요합니다."
            case .receipt: return "설치 프로그램(pkg)이 남긴 설치 기록. 지울 때 암호가 필요합니다."
            case .sharedData: return "모든 사용자 계정이 함께 쓰는 /Users/Shared에 앱(주로 게임 런처)이 남긴 데이터."
            case .relocated: return "macOS 업데이트 때 새 시스템과 맞지 않아 옮겨 둔 예전 설정 파일. 안을 확인했다면 지워도 됩니다. 암호가 필요합니다."
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
            case .exact: return "확실"
            case .likely: return "유력"
            case .guessed: return "추정"
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
