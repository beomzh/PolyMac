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
        context.hotkey("recognizeTable", KeyCombo(kVK_ANSI_6, [.control, .shift]), L("영역 선택 → 표 복사 (엑셀·Markdown)", "Select area → copy table (Excel, Markdown)")) {
            Task { @MainActor in
                guard let capture = await RegionCapture.selectRegion() else { return }
                await OCRRunner.recognizeTableAndCopy(capture.image)
            }
        }
        // 단축어: polymac://ocr, polymac://ocr-table?format=markdown — 클립보드 이미지를 읽어 결과를 클립보드에
        URLActions.register("ocr") { [weak self] _ in
            guard let image = self?.clipboardImage() else { return false }
            return await OCRRunner.recognizeAndCopy(image)
        }
        URLActions.register("ocr-table") { [weak self] query in
            guard let image = self?.clipboardImage() else { return false }
            return await OCRRunner.recognizeTableAndCopy(image, format: query["format"].flatMap(TableFormat.init(rawValue:)) ?? .current)
        }
    }

    public func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: L("클립보드 이미지에서 텍스트 추출", "Extract Text from Clipboard Image"), action: #selector(recognizeFromMenu), keyEquivalent: "")
        item.target = self
        let table = NSMenuItem(title: L("클립보드 이미지에서 표 추출", "Extract Table from Clipboard Image"), action: #selector(recognizeTableFromMenu), keyEquivalent: "")
        table.target = self
        let tableFormat = NSMenuItem(title: L("표 형식: ", "Table format: ") + Self.title(TableFormat.current), action: nil, keyEquivalent: "")
        let formats = NSMenu()
        for format in TableFormat.allCases {
            let option = NSMenuItem(title: Self.title(format), action: #selector(setTableFormat(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = format.rawValue
            option.state = format == TableFormat.current ? .on : .off
            formats.addItem(option)
        }
        if !TableRecognizer.isAvailable {
            formats.addItem(.separator())
            let note = NSMenuItem(title: L("표 인식은 macOS 26 이상 — 지금은 일반 텍스트로 복사", "Tables need macOS 26 — plain text for now"), action: nil, keyEquivalent: "")
            note.isEnabled = false
            formats.addItem(note)
        }
        tableFormat.submenu = formats
        let allow = NSMenuItem(title: L("단축어·URL로 부르기 허용", "Allow Shortcuts & URLs"), action: #selector(toggleURLActions), keyEquivalent: "")
        allow.target = self
        allow.state = URLActions.isAllowed ? .on : .off
        allow.toolTip = L("단축어 앱의 \"X-Callback URL 열기\"로 polymac://ocr 또는 polymac://ocr-table을 부르면 클립보드 이미지를 읽어 결과를 클립보드에 넣습니다.",
                          "Run polymac://ocr or polymac://ocr-table from Shortcuts (Open X-Callback URL) to read the clipboard image into the clipboard.")
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
        return [item, table, lines, tableFormat, allow]
    }

    private static func title(_ format: TableFormat) -> String {
        switch format {
        case .tsv: return L("엑셀·Numbers (탭으로 나눔)", "Excel / Numbers (tab-separated)")
        case .markdown: return L("Markdown 표", "Markdown table")
        }
    }

    @objc private func setTableFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let format = TableFormat(rawValue: raw) else { return }
        TableFormat.current = format
        context.toast(L("표 형식: ", "Table format: ") + Self.title(format))
    }

    @objc private func toggleURLActions() {
        URLActions.isAllowed.toggle()
        if URLActions.isAllowed {
            Toast.show(L("단축어·URL로 부르기를 허용했습니다", "Shortcuts & URLs allowed"), content: "polymac://ocr · polymac://ocr-table", duration: 3)
        } else {
            context.toast(L("단축어·URL로 부르기를 껐습니다", "Shortcuts & URLs turned off"))
        }
    }

    @objc private func recognizeTableFromMenu() {
        guard let image = clipboardImage() else { return }
        Task { @MainActor in await OCRRunner.recognizeTableAndCopy(image) }
    }

    /// 없으면 안내하고 nil
    private func clipboardImage() -> CGImage? {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            context.toast(L("클립보드에 이미지가 없습니다", "No image on the clipboard"))
            return nil
        }
        return cg
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
        guard let cg = clipboardImage() else { return }
        Task { @MainActor in await OCRRunner.recognizeAndCopy(cg) }
    }

    public func deactivate() {
        context.unregisterHotkeys()
        URLActions.unregister("ocr")
        URLActions.unregister("ocr-table")
    }
}
