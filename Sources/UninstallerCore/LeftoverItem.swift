import Foundation

/// 앱 삭제 시 발견된 잔여 항목. UI 없는 순수 로직이라 PolyMacUninstaller.app과 테스트에서 공용으로 쓴다.
public struct LeftoverItem: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case appSupport, caches, preferences, containers, groupContainers
        case savedState, launchAgent, launchDaemon, privilegedHelper, logs, receipt, other
    }

    /// 이 항목을 해당 앱의 것으로 판단한 근거.
    public enum Confidence: Int, Sendable, Comparable {
        case guessed = 0   // 이름 유사 매칭 — 기본 체크 해제
        case likely = 1    // Team ID 일치, pkg 영수증 기록
        case exact = 2     // Bundle ID 정확히 일치

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let url: URL
    public let kind: Kind
    public let confidence: Confidence
    public let sizeBytes: Int64
    public let requiresAdmin: Bool

    public init(url: URL, kind: Kind, confidence: Confidence, sizeBytes: Int64, requiresAdmin: Bool = false) {
        self.url = url
        self.kind = kind
        self.confidence = confidence
        self.sizeBytes = sizeBytes
        self.requiresAdmin = requiresAdmin
    }
}
