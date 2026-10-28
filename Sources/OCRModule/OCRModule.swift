import AppKit
import Carbon.HIToolbox
import PolyMacCore

@MainActor
public final class OCRModule: PolyMacModule {
    public static let descriptor = ModuleDescriptor(
        id: "ocr",
        displayName: ("텍스트 추출 (OCR)", "Text Recognition (OCR)"),
        summary: ("화면 영역의 글자·QR 코드를 읽어 복사 (기기 안에서만)", "Read text and QR codes on screen and copy them (on-device only)"),
        permissions: [.screenRecording]
    )

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public func activate() throws {
        context.hotkey("recognizeRegion", KeyCombo(kVK_ANSI_2, [.control, .shift]), L("영역 선택 → 텍스트 복사", "Select area → copy text")) {
            Task { @MainActor in
                guard let capture = await RegionCapture.selectRegion() else { return }
                await OCRRunner.recognizeAndCopy(capture.image)
            }
        }
        context.hotkey("recognizeClipboardImage", KeyCombo(kVK_ANSI_5, [.control, .shift]), L("클립보드 이미지 → 텍스트 복사", "Clipboard image → copy text")) { [weak self] in
            self?.recognizeClipboardImage()
        }
    }

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: L("클립보드 이미지에서 텍스트 추출", "Extract Text from Clipboard Image"), action: #selector(recognizeFromMenu), keyEquivalent: "")
        item.target = self
        let lines = NSMenuItem(title: L("줄바꿈: ", "Line breaks: ") + Self.title(OCRLineMode.current), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mode in OCRLineMode.allCases {
            let option = NSMenuItem(title: Self.title(mode), action: #selector(setLineMode(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = mode.rawValue
            option.state = mode == OCRLineMode.current ? .on : .off
            sub.addItem(option)
        }
        lines.submenu = sub
        return [item, lines]
    }

    private static func title(_ mode: OCRLineMode) -> String {
        switch mode {
        case .keep: return L("보이는 줄 그대로", "Keep lines as shown")
        case .paragraphs: return L("문단으로 잇기", "Join into paragraphs")
        case .singleLine: return L("한 줄로", "Single line")
        }
    }

    @objc private func setLineMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = OCRLineMode(rawValue: raw) else { return }
        OCRLineMode.current = mode
        context.toast(L("텍스트 추출 줄바꿈: ", "Text recognition line breaks: ") + Self.title(mode))
    }

    @objc private func recognizeFromMenu() { recognizeClipboardImage() }

    /// 캡처해서 클립보드에 넣어 둔 이미지(다른 캡처 앱 포함)에서 글자를 뽑아 같은 클립보드에 텍스트로 넣는다.
    private func recognizeClipboardImage() {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            context.toast(L("클립보드에 이미지가 없습니다", "No image on the clipboard"))
            return
        }
        Task { @MainActor in await OCRRunner.recognizeAndCopy(cg) }
    }

    public func deactivate() {
        context.unregisterHotkeys()
    }
}
