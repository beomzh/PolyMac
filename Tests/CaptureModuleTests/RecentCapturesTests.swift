import AppKit
import Foundation
import Testing
@testable import CaptureModule
@testable import PolyMacCore

private func solidImage(width: Int, height: Int, gray: CGFloat = 0.5) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@MainActor
@Test func recentCapturesKeepNewestFirstWithinCapacity() throws {
    let recent = RecentCaptures()
    for n in 0..<(RecentCaptures.capacity + 3) {
        let capture = CaptureResult(image: solidImage(width: 10 + n, height: 8), scale: 2, screenRect: .zero)
        recent.insert(try #require(RecentCaptures.entry(from: capture, date: Date(timeIntervalSince1970: Double(n)))))
    }
    #expect(recent.entries.count == RecentCaptures.capacity)
    #expect(recent.entries.first?.pixelSize.width == CGFloat(10 + RecentCaptures.capacity + 2))
    #expect(recent.entries.map(\.date) == recent.entries.map(\.date).sorted(by: >))
    recent.clear()
    #expect(recent.entries.isEmpty)
}

@MainActor
@Test func recentCaptureRoundTripsImageScaleAndAnnotations() throws {
    let recent = RecentCaptures()
    let note = Annotation(tool: .rectangle, start: CGPoint(x: 1, y: 2), color: .systemRed)
    let capture = CaptureResult(image: solidImage(width: 40, height: 20), scale: 2, screenRect: .zero, annotations: [note])
    let entry = try #require(RecentCaptures.entry(from: capture))
    recent.insert(entry)
    let back = try #require(recent.capture(entry.id))
    #expect(back.image.width == 40 && back.image.height == 20)
    #expect(back.scale == 2)
    #expect(back.annotations.count == 1)
    #expect(entry.thumbnail.size.width == 48)
    #expect(recent.capture(UUID()) == nil)
}

@Test func pinExportWritesPrivatePNGAndCleansOldFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PolyMacTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let first = try PinExport.write(solidImage(width: 4, height: 4), now: now, in: folder)
    let second = try PinExport.write(solidImage(width: 4, height: 4), now: now, in: folder)
    #expect(first != second)
    #expect(first.pathExtension == "png")
    #expect(NSImage(contentsOf: first) != nil)
    let mode = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)

    // 파일 시각은 실제 지금이라 1시간 뒤로 잡으면 둘 다 지워진다
    PinExport.cleanUp(olderThan: 60, now: Date().addingTimeInterval(30), in: folder)
    #expect(FileManager.default.fileExists(atPath: first.path))
    PinExport.cleanUp(olderThan: 3600, now: Date().addingTimeInterval(7200), in: folder)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}
