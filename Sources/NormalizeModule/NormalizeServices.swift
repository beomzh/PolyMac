import AppKit
import PolyMacCore

/// Finder 우클릭 메뉴(macOS 서비스)에서 고른 항목으로 하는 일
public extension NormalizeModule {
    /// 고른 항목과 그 안쪽의 자소분리 이름을 모두 고친다. 바꿀 개수를 먼저 보여 주고 확인을 받는다.
    func fixNames(_ urls: [URL]) {
        let count = urls.reduce(0) { $0 + HangulNormalizer.countTree($1) }
        guard count > 0 else {
            context.toast(L("자소분리된 파일명이 없습니다", "No decomposed filenames found"))
            return
        }
        let alert = NSAlert()
        alert.messageText = L("한글 파일명 \(count)개를 정리할까요?", "Fix \(count) Korean filename(s)?")
        alert.informativeText = L("고른 항목과 그 안쪽 폴더의 풀어진 한글 이름(NFD)을 완성형(NFC)으로 바꿉니다. 앱·번들 안과 숨김 파일은 건드리지 않습니다.",
                                  "Decomposed (NFD) Korean names in the selection and its subfolders become composed (NFC). Inside apps/bundles and hidden files are left alone.")
        alert.addButton(withTitle: L("정리", "Fix"))
        alert.addButton(withTitle: L("취소", "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var fixed = 0, failed = 0
        for url in urls {
            do { fixed += try HangulNormalizer.normalizeTree(url).count } catch { failed += 1 }
        }
        context.logger.info("fixNames fixed=\(fixed) failed=\(failed)")
        context.toast(failed == 0 ? L("한글 파일명 \(fixed)개를 정리했습니다", "Fixed \(fixed) Korean filename(s)")
                                  : L("\(fixed)개 정리, \(failed)개 항목 실패", "Fixed \(fixed), \(failed) item(s) failed"))
    }

    /// Windows에서 한글 이름이 깨지지 않는 zip을 고른 항목 옆에 만든다
    func makeWindowsZip(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let folder = first.deletingLastPathComponent()
        let base = urls.count == 1 ? WindowsZip.nfcName(first) : L("압축", "Archive")
        let destination = Self.freeName(base + ".zip", in: folder)
        context.toast(L("압축하는 중…", "Compressing…"))
        let context = context
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WindowsZip.create(from: urls, to: destination) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success(let files):
                        context.toast(L("Windows용 압축을 만들었습니다 (파일 \(files)개)\n\(destination.lastPathComponent)",
                                        "Created a Windows-friendly zip (\(files) files)\n\(destination.lastPathComponent)"))
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    case .failure(let error):
                        context.logger.error("zip failed: \(error.localizedDescription, privacy: .public)")
                        context.toast(L("압축 실패: ", "Compression failed: ") + error.localizedDescription, duration: 4)
                    }
                }
            }
        }
    }

    nonisolated private static func freeName(_ name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
