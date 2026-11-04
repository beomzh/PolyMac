import AppKit
import PolyMacCore

/// 번역 결과 창. 번역과 원문을 나란히 보고, 복사는 누를 때만 한다. 다른 앱의 입력을 뺏지 않게 앞으로 나오지 않는 패널.
@MainActor
final class TranslationResultPanel: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static var current: TranslationResultPanel?

    private let panel: Panel
    private let languages = NSTextField(labelWithString: L("번역 중…", "Translating…"))
    private let spinner = NSProgressIndicator()
    private let translationView: NSTextView
    private let originalView: NSTextView
    private let copyButton: NSButton
    private let original: String
    private var translation: String?

    var isShowingResult: Bool { translation != nil }

    /// 번역이 끝나기 전에 띄운다. 앞의 결과 창은 닫는다.
    static func show(original: String) -> TranslationResultPanel {
        current?.dismiss()
        let result = TranslationResultPanel(original: original)
        current = result
        result.panel.makeKeyAndOrderFront(nil)
        return result
    }

    private init(original: String) {
        self.original = original
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        let translationScroll = NSTextView.scrollableTextView()
        let originalScroll = NSTextView.scrollableTextView()
        translationView = translationScroll.documentView as! NSTextView
        originalView = originalScroll.documentView as! NSTextView
        copyButton = NSButton(title: L("번역 복사", "Copy Translation"), target: nil, action: nil)
        super.init()
        panel.title = L("번역", "Translation")
        panel.level = .floating
        panel.minSize = NSSize(width: 320, height: 240)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        for (view, size, color) in [(translationView, CGFloat(15), NSColor.labelColor), (originalView, CGFloat(12), NSColor.secondaryLabelColor)] {
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.font = .systemFont(ofSize: size)
            view.textColor = color
            view.textContainerInset = NSSize(width: 4, height: 6)
        }
        originalView.string = original
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        languages.font = .systemFont(ofSize: 12, weight: .medium)
        languages.textColor = .secondaryLabelColor
        let header = NSStackView(views: [spinner, languages])
        header.spacing = 6

        let originalTitle = NSTextField(labelWithString: L("원문", "Original"))
        originalTitle.font = .systemFont(ofSize: 11, weight: .medium)
        originalTitle.textColor = .tertiaryLabelColor

        copyButton.target = self
        copyButton.action = #selector(copyTranslation)
        copyButton.keyEquivalent = "\r"
        copyButton.isEnabled = false
        let copyOriginalButton = NSButton(title: L("원문 복사", "Copy Original"), target: self, action: #selector(copyOriginal))
        let closeButton = NSButton(title: L("닫기", "Close"), target: self, action: #selector(closeTapped))
        closeButton.keyEquivalent = "\u{1b}"
        // 앱이 앞에 없어 편집 메뉴가 받지 못하는 ⌘C — 보이지 않는 단추로 받는다
        let selectionCopy = NSButton(title: "", target: self, action: #selector(copySelection))
        selectionCopy.keyEquivalent = "c"
        selectionCopy.keyEquivalentModifierMask = .command
        selectionCopy.isBordered = false
        selectionCopy.frame = .zero
        let buttons = NSStackView(views: [closeButton, NSView(), copyOriginalButton, copyButton])
        buttons.spacing = 8
        buttons.addSubview(selectionCopy)

        let stack = NSStackView(views: [header, translationScroll, originalTitle, originalScroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        for view in [translationScroll, originalScroll, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
        translationScroll.heightAnchor.constraint(equalTo: originalScroll.heightAnchor, multiplier: 1.6).isActive = true
        originalScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        panel.contentView = stack

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.midY - panel.frame.height / 2))
        }
    }

    func show(translation: String, source: String, target: String) {
        self.translation = translation
        translationView.string = translation
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        languages.stringValue = "\(Self.name(source)) → \(Self.name(target))"
        copyButton.isEnabled = true
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    func dismiss() {
        panel.delegate = nil
        panel.close()
        if Self.current === self { Self.current = nil }
    }

    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }

    private func copy(_ text: String, message: String) {
        PasteboardWriter.copy(text, origin: .ocr)
        Toast.show(message)
        dismiss()
    }

    @objc private func copyTranslation() {
        guard let translation else { return }
        copy(translation, message: L("번역을 복사했습니다", "Translation copied"))
    }

    @objc private func copyOriginal() {
        copy(original, message: L("원문을 복사했습니다", "Original copied"))
    }

    /// 고른 부분이 있으면 그 부분만, 없으면 번역 전체. 고른 게 없고 번역 전이면 아무것도 안 한다.
    @objc private func copySelection() {
        for view in [translationView, originalView] {
            let range = view.selectedRange()
            guard range.length > 0 else { continue }
            copy((view.string as NSString).substring(with: range), message: L("고른 부분을 복사했습니다", "Selection copied"))
            return
        }
        copyTranslation()
    }

    @objc private func closeTapped() {
        dismiss()
    }
}
