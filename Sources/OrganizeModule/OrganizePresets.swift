import Foundation
import PolyMacCore

/// 기본 제공 규칙. 전부 꺼진 상태로 제공하고 사용자가 골라서 켠다.
/// 이름이 현재 언어를 따르도록 부를 때마다 만든다 (저장된 규칙은 만든 때의 이름 그대로).
public enum OrganizePresets {
    public static var installersToTrash: OrganizeRule { OrganizeRule(
        name: L("설치 파일 7일 후 휴지통", "Trash installers after 7 days"),
        isEnabled: false,
        conditions: [.kind(kinds: [.installer]), .addedMoreThan(days: 7)],
        actions: [.trash]
    ) }

    public static var documentsByMonth: OrganizeRule { OrganizeRule(
        name: L("문서는 월별 폴더로", "Documents into monthly folders"),
        isEnabled: false,
        conditions: [.kind(kinds: [.document])],
        actions: [.move(to: L("~/Documents/받은문서/{yyyy}-{MM}", "~/Documents/Downloaded Documents/{yyyy}-{MM}"))]
    ) }

    public static var imagesToPictures: OrganizeRule { OrganizeRule(
        name: L("이미지는 사진 폴더로", "Images to Pictures"),
        isEnabled: false,
        conditions: [.kind(kinds: [.image])],
        actions: [.move(to: "~/Pictures/Downloads")]
    ) }

    public static var bySourceSite: OrganizeRule { OrganizeRule(
        name: L("받은 사이트별 폴더로", "Folders by source website"),
        isEnabled: false,
        conditions: [.not(condition: .kind(kinds: [.installer]))],
        actions: [.move(to: "~/Downloads/{domain}")]
    ) }

    public static var staleNotice: OrganizeRule { OrganizeRule(
        name: L("30일 안 연 파일 알림", "Notify about files unopened for 30 days"),
        isEnabled: false,
        conditions: [.notOpenedFor(days: 30)],
        actions: [.notify],
        stopAfterMatch: false
    ) }

    public static var all: [OrganizeRule] { [installersToTrash, documentsByMonth, imagesToPictures, bySourceSite, staleNotice] }
}
