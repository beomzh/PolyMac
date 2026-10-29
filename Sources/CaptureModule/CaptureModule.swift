import AppKit
import Carbon.HIToolbox
import OCRModule
import PolyMacCore

@MainActor
public final class CaptureModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "capture",
        displayName: ("캡처 · 핀", "Capture & Pin"),
        summary: ("화면 일부를 캡처해 복사·표시·핀으로 띄우기", "Capture part of the screen, mark it up, copy or pin it"),
        permissions: [.screenRecording]
    )

    private let context: ModuleContext
    private let recent = RecentCaptures()

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        // 저장 키(id)는 바꾸지 않는다 — 사용자가 바꾼 단축키가 이 키로 저장돼 있다
        context.hotkey("captureToClipboard", KeyCombo(kVK_ANSI_1, [.control, .shift]), L("영역 캡처 → 편집 도구 (표시·핀·텍스트 추출·저장)", "Capture area → editor (markup, pin, text, save)")) { [weak self] in
            Task { @MainActor in
                guard let (capture, action) = await RegionCapture.captureAndEdit() else { return }
                self?.recent.add(capture)
                CaptureModule.finish(capture, action)
            }
        }
        context.hotkey("captureToPin", KeyCombo(kVK_ANSI_3, [.control, .shift]), L("영역 캡처 → 바로 화면에 고정", "Capture area → pin on screen")) { [weak self] in
            Task { @MainActor in
                guard let capture = await RegionCapture.selectRegion() else { return }
                self?.recent.add(capture)
                PinPanel.show(capture, at: capture.screenRect)
            }
        }
        context.hotkey("pinClipboardImage", KeyCombo(kVK_ANSI_4, [.control, .shift]), L("클립보드 이미지 → 화면에 고정", "Clipboard image → pin on screen")) { [weak self] in
            self?.pinClipboardImage()
        }
        // 클립보드 기록 등 다른 모듈의 이미지를 핀으로
        PinService.handler = { image, scale in
            PinPanel.show(CaptureResult(image: image, scale: scale, screenRect: .zero), at: nil)
        }
    }

    public func deactivate() {
        context.unregisterHotkeys()
        PinService.handler = nil
        PinPanel.closeAll()
        recent.clear()
        PinExport.cleanUp(olderThan: 0)
    }

    public func menuItems() -> [NSMenuItem] {
        let close = NSMenuItem(title: L("고정된 캡처 모두 닫기 (\(PinPanel.openCount)개)", "Close All Pinned Captures (\(PinPanel.openCount))"), action: #selector(closeAllPins), keyEquivalent: "")
        close.target = self
        close.isEnabled = PinPanel.openCount > 0
        var items = [close]
        let through = PinPanel.clickThroughCount
        if through > 0 {
            let off = NSMenuItem(title: L("클릭 통과 끄기 (\(through)개)", "Turn Off Click-Through (\(through))"), action: #selector(endClickThrough), keyEquivalent: "")
            off.target = self
            items.append(off)
        }
        items.append(recentMenuItem())
        return items
    }

    private func recentMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("최근 캡처 다시 고정", "Pin a Recent Capture"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        for entry in recent.entries {
            let title = "\(time.string(from: entry.date)) · \(Int(entry.pixelSize.width / entry.scale))×\(Int(entry.pixelSize.height / entry.scale))"
            let row = NSMenuItem(title: title, action: #selector(pinRecent(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = entry.id
            row.image = entry.thumbnail
            sub.addItem(row)
        }
        if recent.entries.isEmpty {
            let none = NSMenuItem(title: L("아직 없음", "None yet"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            sub.addItem(.separator())
            let clear = NSMenuItem(title: L("목록 지우기", "Clear List"), action: #selector(clearRecent), keyEquivalent: "")
            clear.target = self
            sub.addItem(clear)
        }
        let note = NSMenuItem(title: L("최근 \(RecentCaptures.capacity)개, 메모리에만 — PolyMac을 끄면 사라집니다", "Last \(RecentCaptures.capacity), in memory only — gone when PolyMac quits"),
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        sub.addItem(note)
        item.submenu = sub
        return item
    }

    @objc private func pinRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let capture = recent.capture(id) else { return }
        PinPanel.show(capture, at: nil)
    }

    @objc private func clearRecent() {
        recent.clear()
    }

    @objc private func endClickThrough() {
        PinPanel.endClickThroughAll()
    }

    private static func finish(_ capture: CaptureResult, _ action: CaptureAction) {
        switch action {
        case .copy:
            PasteboardWriter.copy(capture.compositeImage, scale: capture.scale, origin: .capture)
            Toast.show(L("캡처를 클립보드에 복사했습니다", "Capture copied to the clipboard"))
        case .pin:
            PinPanel.show(capture, at: capture.screenRect)
        case .ocr:
            // 그린 표시가 글자 인식을 방해하지 않게 원본으로
            Task { @MainActor in await OCRRunner.recognizeAndCopy(capture.image) }
        case .save:
            PinPanel.save(capture.compositeImage)
        }
    }

    @objc private func closeAllPins() {
        PinPanel.closeAll()
    }

    private func pinClipboardImage() {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            context.toast(L("클립보드에 이미지가 없습니다", "No image on the clipboard"))
            return
        }
        let scale = image.size.width > 0 ? max(CGFloat(cg.width) / image.size.width, 1) : 1
        PinPanel.show(CaptureResult(image: cg, scale: scale, screenRect: .zero), at: nil)
    }
}
