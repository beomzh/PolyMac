import AppKit
import PolyMacCore

/// 최근 캡처 몇 개를 메모리에만 둔다 (디스크에 쓰지 않음 — PolyMac을 끄면 사라진다).
/// 원본은 PNG로 줄여 들고, 표시(Annotation)는 따로 들고 있어 다시 고정해도 표시를 고칠 수 있다.
@MainActor
final class RecentCaptures {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let png: Data
        let scale: CGFloat
        let annotations: [Annotation]
        let pixelSize: CGSize
        let thumbnail: NSImage
    }

    static let capacity = 10
    private(set) var entries: [Entry] = []

    /// PNG로 줄이는 일은 큰 캡처에서 수십 ms 걸려 백그라운드에서
    func add(_ capture: CaptureResult) {
        nonisolated(unsafe) let capture = capture
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let entry = Self.entry(from: capture)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let entry { self?.insert(entry) }
                }
            }
        }
    }

    func insert(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    func capture(_ id: UUID) -> CaptureResult? {
        guard let entry = entries.first(where: { $0.id == id }),
              let source = CGImageSourceCreateWithData(entry.png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return CaptureResult(image: image, scale: entry.scale, screenRect: .zero, annotations: entry.annotations)
    }

    func clear() {
        entries.removeAll()
    }

    nonisolated static func entry(from capture: CaptureResult, date: Date = Date()) -> Entry? {
        guard let png = NSBitmapImageRep(cgImage: capture.image).representation(using: .png, properties: [:]) else { return nil }
        let size = CGSize(width: capture.image.width, height: capture.image.height)
        return Entry(date: date, png: png, scale: capture.scale, annotations: capture.annotations, pixelSize: size,
                     thumbnail: thumbnail(capture.compositeImage))
    }

    /// 메뉴에 넣을 작은 그림 (긴 쪽 48 pt)
    private nonisolated static func thumbnail(_ image: CGImage) -> NSImage {
        let longest = CGFloat(max(image.width, image.height, 1))
        let factor = 48 / longest
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor))
    }
}

/// 핀을 다른 앱으로 끌어 넣을 때 쓰는 임시 PNG. 사용자 임시 폴더(다른 사용자는 못 읽음) 안에 두고 1시간 지나면 지운다.
enum PinExport {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PolyMac-drag", isDirectory: true)
    }

    /// folder: 테스트에서만 바꾼다 (실행 중인 앱의 임시 파일을 건드리지 않게)
    static func write(_ image: CGImage, now: Date = Date(), in folder: URL = directory) throws -> URL {
        cleanUp(olderThan: 3600, now: now, in: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ModuleError(L("이미지를 PNG로 만들지 못했습니다", "Could not make a PNG"))
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        var url = folder.appendingPathComponent("PolyMac \(stamp.string(from: now)).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("PolyMac \(stamp.string(from: now)) \(n).png")
            n += 1
        }
        try AppPaths.writePrivate(data, to: url)
        return url
    }

    /// age: 이보다 오래된 파일만 (0이면 모두)
    static func cleanUp(olderThan age: TimeInterval, now: Date = Date(), in folder: URL = directory) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if now.timeIntervalSince(modified) >= age { try? FileManager.default.removeItem(at: file) }
        }
    }
}
