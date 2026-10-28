import Foundation
import PolyMacCore

/// 한글 파일명 자동 정리가 감시할 폴더 목록. 환경 설정 › 한글 파일명에서 바꾸고 UserDefaults "normalize.folders"에 저장한다.
/// 터미널에서도 지정할 수 있다:
///   defaults write dev.polymac.app normalize.folders -array "~/Downloads" "~/Documents/받은파일"
/// 끈 폴더는 "normalize.disabledFolders"에 따로 둬서 목록에서 지우지 않고 잠시 쉬게 할 수 있다.
public enum NormalizeFolders {
    public static let foldersKey = "normalize.folders"
    public static let disabledKey = "normalize.disabledFolders"
    /// 예전 버전의 "추가 폴더" — 처음 한 번 새 목록으로 옮긴다
    static let legacyExtraKey = "normalize.extraFolders"
    public static let defaults = ["~/Downloads", "~/Desktop"]

    /// 목록이 바뀌면 보낸다 (모듈이 감시를 다시 시작)
    public static let didChange = Notification.Name("dev.polymac.normalize.foldersChanged")

    public struct Folder: Equatable, Hashable, Sendable {
        /// `~`로 줄인 경로
        public var path: String
        public var isEnabled: Bool
        public init(path: String, isEnabled: Bool = true) {
            self.path = path
            self.isEnabled = isEnabled
        }
        public var expandedPath: String { NSString(string: path).expandingTildeInPath }
    }

    public static func load(from store: UserDefaults = .standard) -> [Folder] {
        let paths: [String]
        if let saved = store.stringArray(forKey: foldersKey) {
            paths = saved
        } else {
            paths = defaults + (store.stringArray(forKey: legacyExtraKey) ?? [])
        }
        let disabled = Set(store.stringArray(forKey: disabledKey) ?? [])
        var seen = Set<String>()
        return paths.map(abbreviate).filter { seen.insert($0).inserted }.map { Folder(path: $0, isEnabled: !disabled.contains($0)) }
    }

    public static func save(_ folders: [Folder], to store: UserDefaults = .standard) {
        store.set(folders.map(\.path), forKey: foldersKey)
        store.set(folders.filter { !$0.isEnabled }.map(\.path), forKey: disabledKey)
        store.removeObject(forKey: legacyExtraKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// 켜진 폴더 중 허용되는 것만, 펼친 경로로
    public static func activePaths(from store: UserDefaults = .standard) -> [String] {
        load(from: store).filter(\.isEnabled).map(\.expandedPath).filter { problem(with: $0) == nil }
    }

    /// 감시하면 안 되는 폴더면 이유. 홈 폴더 안의 실제 폴더만 허용하고, 앱 데이터(~/Library)와 홈 폴더 자체는 막는다 —
    /// 실행 중인 앱이 쓰는 파일 이름을 바꾸지 않도록.
    public static func problem(with path: String, home: String = NSHomeDirectory()) -> String? {
        let resolved = (NSString(string: path).expandingTildeInPath as NSString).resolvingSymlinksInPath
        let homeResolved = (home as NSString).resolvingSymlinksInPath
        if resolved == homeResolved { return L("홈 폴더 전체는 지정할 수 없습니다", "The whole home folder can't be watched") }
        guard resolved.hasPrefix(homeResolved + "/") else { return L("홈 폴더 안의 폴더만 지정할 수 있습니다", "Only folders inside your home folder can be watched") }
        if resolved.hasPrefix(homeResolved + "/Library/") || resolved == homeResolved + "/Library" {
            return L("~/Library(앱 데이터)는 지정할 수 없습니다", "~/Library (app data) can't be watched")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory), isDirectory.boolValue else {
            return L("폴더가 없습니다", "Folder not found")
        }
        return nil
    }

    static func abbreviate(_ path: String) -> String {
        (NSString(string: path).expandingTildeInPath as NSString).abbreviatingWithTildeInPath
    }
}
