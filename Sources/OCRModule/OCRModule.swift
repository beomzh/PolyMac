import AppKit
import Carbon.HIToolbox
import PolyMacCore

@MainActor
public final class OCRModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "ocr",
        displayName: "텍스트 추출 (OCR)",
        permissions: [.screenRecording]
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        context.hotkey("recognizeRegion", KeyCombo(kVK_ANSI_2, [.control, .shift]), "영역 선택 → 텍스트 복사") {
            Task { @MainActor in
                guard let capture = await RegionCapture.selectRegion() else { return }
                await OCRRunner.recognizeAndCopy(capture.image)
            }
        }
        context.hotkey("recognizeClipboardImage", KeyCombo(kVK_ANSI_5, [.control, .shift]), "클립보드 이미지 → 텍스트 복사") { [weak self] in
            self?.recognizeClipboardImage()
        }
    }

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "클립보드 이미지에서 텍스트 추출", action: #selector(recognizeFromMenu), keyEquivalent: "")
        item.target = self
        return [item]
    }

    @objc private func recognizeFromMenu() { recognizeClipboardImage() }

    /// 캡처해서 클립보드에 넣어 둔 이미지(다른 캡처 앱 포함)에서 글자를 뽑아 같은 클립보드에 텍스트로 넣는다.
    private func recognizeClipboardImage() {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            context.toast("클립보드에 이미지가 없습니다")
            return
        }
        Task { @MainActor in await OCRRunner.recognizeAndCopy(cg) }
    }

    public func deactivate() {
        context.unregisterHotkeys()
    }
}
