import AppKit
import Carbon.HIToolbox
import OCRModule
import PolyMacCore

@MainActor
public final class CaptureModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "capture",
        displayName: "캡처 · 핀",
        permissions: [.screenRecording]
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        // 저장 키(id)는 바꾸지 않는다 — 사용자가 바꾼 단축키가 이 키로 저장돼 있다
        context.hotkey("captureToClipboard", KeyCombo(kVK_ANSI_1, [.control, .shift]), "영역 캡처 → 편집 도구 (표시·핀·텍스트 추출·저장)") {
            Task { @MainActor in
                guard let (capture, action) = await RegionCapture.captureAndEdit() else { return }
                CaptureModule.finish(capture, action)
            }
        }
        context.hotkey("captureToPin", KeyCombo(kVK_ANSI_3, [.control, .shift]), "영역 캡처 → 바로 화면에 고정") {
            Task { @MainActor in
                guard let capture = await RegionCapture.selectRegion() else { return }
                PinPanel.show(capture, at: capture.screenRect)
            }
        }
        context.hotkey("pinClipboardImage", KeyCombo(kVK_ANSI_4, [.control, .shift]), "클립보드 이미지 → 화면에 고정") { [weak self] in
            self?.pinClipboardImage()
        }
    }

    public func deactivate() {
        context.unregisterHotkeys()
        PinPanel.closeAll()
    }

    public func menuItems() -> [NSMenuItem] {
        let close = NSMenuItem(title: "고정된 캡처 모두 닫기 (\(PinPanel.openCount)개)", action: #selector(closeAllPins), keyEquivalent: "")
        close.target = self
        close.isEnabled = PinPanel.openCount > 0
        return [close]
    }

    private static func finish(_ capture: CaptureResult, _ action: CaptureAction) {
        switch action {
        case .copy:
            PasteboardWriter.copy(capture.compositeImage, scale: capture.scale)
            Toast.show("캡처를 클립보드에 복사했습니다")
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
            context.toast("클립보드에 이미지가 없습니다")
            return
        }
        let scale = image.size.width > 0 ? max(CGFloat(cg.width) / image.size.width, 1) : 1
        PinPanel.show(CaptureResult(image: cg, scale: scale, screenRect: .zero), at: nil)
    }
}
