import Foundation

/// 기본 제공 규칙. 전부 꺼진 상태로 제공하고 사용자가 골라서 켠다.
public enum OrganizePresets {
    public static let installersToTrash = OrganizeRule(
        name: "설치 파일 7일 후 휴지통",
        isEnabled: false,
        conditions: [.kind(kinds: [.installer]), .addedMoreThan(days: 7)],
        actions: [.trash]
    )

    public static let documentsByMonth = OrganizeRule(
        name: "문서는 월별 폴더로",
        isEnabled: false,
        conditions: [.kind(kinds: [.document])],
        actions: [.move(to: "~/Documents/받은문서/{yyyy}-{MM}")]
    )

    public static let imagesToPictures = OrganizeRule(
        name: "이미지는 사진 폴더로",
        isEnabled: false,
        conditions: [.kind(kinds: [.image])],
        actions: [.move(to: "~/Pictures/Downloads")]
    )

    public static let bySourceSite = OrganizeRule(
        name: "받은 사이트별 폴더로",
        isEnabled: false,
        conditions: [.not(condition: .kind(kinds: [.installer]))],
        actions: [.move(to: "~/Downloads/{domain}")]
    )

    public static let staleNotice = OrganizeRule(
        name: "30일 안 연 파일 알림",
        isEnabled: false,
        conditions: [.notOpenedFor(days: 30)],
        actions: [.notify],
        stopAfterMatch: false
    )

    public static let all = [installersToTrash, documentsByMonth, imagesToPictures, bySourceSite, staleNotice]
}
