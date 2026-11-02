import AppKit
import PolyMacCore
import Sparkle
import os

/// Sparkle 자동 업데이트 — PolyMac에서 네트워크를 쓰는 유일한 곳.
/// 기본은 꺼져 있다: 메뉴의 "업데이트 확인…"을 누르거나 환경 설정에서 자동 확인을 켰을 때만
/// GitHub Releases의 appcast.xml을 읽는다. 받은 파일은 EdDSA 서명(Info.plist SUPublicEDKey)이 맞아야만 설치한다.
/// 공개 키가 없는 빌드(App/sparkle-public-key.txt 없음)에서는 아무것도 하지 않는다.
@MainActor
final class Updater {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: "dev.polymac", category: "update")

    var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        return !key.isEmpty && feed.hasPrefix("https://")
    }

    /// 자동 확인이 꺼져 있으면 시작해도 네트워크를 쓰지 않는다
    func start() {
        guard controller == nil else { return }
        guard isConfigured else {
            logger.info("updates not configured in this build")
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        logger.info("updater started automaticChecks=\(self.automaticallyChecks)")
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            logger.notice("automatic update checks=\(newValue)")
        }
    }

    func checkForUpdates() {
        guard let controller else {
            Toast.show(L("이 빌드는 업데이트 확인을 쓰지 않습니다", "Update checks are not set up in this build"),
                       content: L("직접 빌드한 앱은 git pull 후 다시 빌드하세요", "For a build from source, git pull and build again"))
            return
        }
        logger.notice("manual update check")
        // 메뉴바 전용 앱이라 앞으로 가져와야 업데이트 창이 다른 창 뒤에 숨지 않는다
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
