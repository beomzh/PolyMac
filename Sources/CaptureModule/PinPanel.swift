import AppKit
import OCRModule
import PolyMacCore
import UniformTypeIdentifiers

/// 화면 위에 떠 있는 캡처(핀). 드래그로 이동, ⌘드래그로 다른 앱에 PNG로 넣기, 스크롤로 확대/축소, ⌥+스크롤로 투명도, 더블클릭으로 닫기.
/// 표시(사각형·화살표·펜)는 이미지에 굽지 않고 따로 들고 있어 우클릭 › 표시 편집으로 다시 고칠 수 있다.
@MainActor
final class PinPanel: NSPanel {
    private static var open: Set<PinPanel> = [] {
        didSet { updateEscapeMonitor() }
    }
    static var openCount: Int { open.count }
    private static var escapeMonitor: Any?

    /// 다른 앱을 쓰는 중에도 핀 위에 마우스를 올리고 Esc를 누르면 그 핀을 닫는다.
    /// (Esc만 — 전역 감시는 키를 가로채지 못해 앞의 앱에도 전달되므로, 지워지는 키인 ⌫는 핀을 클릭했을 때만 받는다)
    private static func updateEscapeMonitor() {
        if open.isEmpty, let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        } else if !open.isEmpty, escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return }
                MainActor.assumeIsolated {
                    let mouse = NSEvent.mouseLocation
                    PinPanel.open.filter { $0.frame.contains(mouse) }.max { $0.orderedIndex > $1.orderedIndex }?.closePin()
                }
            }
        }
    }

    private let image: CGImage
    fileprivate let scale: CGFloat
    private let baseSize: NSSize
    private var zoom: CGFloat = 1
    fileprivate var annotations: [Annotation]
    private var editBar: NSPanel?
    fileprivate var markupBar: AnnotationToolbar?

    var isEditingMarkup: Bool { markupBar != nil }

    static func show(_ capture: CaptureResult, at frame: NSRect?) {
        let size = NSSize(width: CGFloat(capture.image.width) / capture.scale, height: CGFloat(capture.image.height) / capture.scale)
        let mouse = NSEvent.mouseLocation
        let rect = frame ?? NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)
        let panel = PinPanel(image: capture.image, scale: capture.scale, annotations: capture.annotations, frame: rect)
        open.insert(panel)
        panel.orderFrontRegardless()
    }

    static func closeAll() {
        open.forEach { $0.closePin() }
    }

    /// 클릭 통과 중인 핀 — 핀을 클릭할 수 없으니 메뉴바에서 끈다
    static var clickThroughCount: Int { open.filter(\.ignoresMouseEvents).count }

    static func endClickThroughAll() {
        open.filter(\.ignoresMouseEvents).forEach { $0.setClickThrough(false) }
    }

    private init(image: CGImage, scale: CGFloat, annotations: [Annotation], frame: NSRect) {
        self.image = image
        self.scale = scale
        self.baseSize = frame.size
        self.annotations = annotations
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        // 배경 끌기로 옮기지 않는다 — macOS가 끌 수 있는 영역을 미리 정해 두어 표시 편집 중에도 핀이 움직였다.
        // 옮기기는 PinCanvasView.mouseDown에서 편집 중이 아닐 때만 performDrag로 한다.
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PinCanvasView(frame: NSRect(origin: .zero, size: frame.size), image: image)
        view.toolTip = L("Esc·⌫ 닫기 · ⌘드래그로 다른 앱에 넣기 · 스크롤 확대 · ⌥스크롤 투명도 · 우클릭 메뉴",
                         "Esc/⌫ close · ⌘-drag into another app · scroll to zoom · ⌥-scroll opacity · right-click for menu")
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        view.pin = self
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    /// 원본 크기 대비 지금 보이는 배율 (표시 좌표 변환용)
    var displayFactor: CGFloat { frame.width / baseSize.width }

    var composite: CGImage { AnnotationRenderer.composite(image, scale: scale, annotations: annotations) }

    func closePin() {
        endEditing()
        orderOut(nil)
        PinPanel.open.remove(self)
    }

    func zoom(by delta: CGFloat) {
        zoom = min(max(zoom * (delta > 0 ? 1.06 : 1 / 1.06), 0.2), 5)
        resize(to: NSSize(width: baseSize.width * zoom, height: baseSize.height * zoom))
    }

    private func resize(to size: NSSize) {
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), display: true)
        placeEditBar()
    }

    /// 켜면 핀 아래 창을 그대로 클릭·스크롤할 수 있다. 테두리를 주황으로 바꿔 구분한다.
    func setClickThrough(_ on: Bool) {
        ignoresMouseEvents = on
        guard let layer = contentView?.layer else { return }
        layer.borderColor = (on ? NSColor.systemOrange : NSColor.systemBlue).withAlphaComponent(on ? 0.8 : 0.6).cgColor
        layer.borderWidth = on ? 2 : 1
    }

    @objc private func turnOnClickThrough() {
        endEditing()
        setClickThrough(true)
        Toast.show(L("클릭 통과 — 핀 아래 창을 그대로 쓸 수 있습니다", "Click-through — use the window under the pin"),
                   content: L("끄기: 메뉴바 › 캡처 · 핀 › 클릭 통과 끄기 · 닫기: 핀 위에서 Esc",
                              "Turn off: menu bar › Capture & Pin › Turn Off Click-Through · Close: Esc over the pin"), duration: 4)
    }

    func adjustOpacity(by delta: CGFloat) {
        alphaValue = min(max(alphaValue + (delta > 0 ? 0.05 : -0.05), 0.2), 1)
    }

    // MARK: - 표시 편집

    @objc func beginEditing() {
        guard markupBar == nil else { return }
        let bar = AnnotationToolbar(output: false)
        bar.select(.rectangle)
        bar.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .undo:
                if !self.annotations.isEmpty { self.annotations.removeLast() }
                self.contentView?.needsDisplay = true
            case .done:
                self.endEditing()
            default:
                break
            }
        }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: bar.frame.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.contentView = bar
        addChildWindow(panel, ordered: .above)
        editBar = panel
        markupBar = bar
        placeEditBar()
        contentView?.window?.invalidateCursorRects(for: contentView!)
    }

    func endEditing() {
        guard let editBar else { return }
        removeChildWindow(editBar)
        editBar.orderOut(nil)
        self.editBar = nil
        markupBar = nil
        contentView?.needsDisplay = true
    }

    private func placeEditBar() {
        guard let editBar else { return }
        let size = editBar.frame.size
        var origin = NSPoint(x: frame.maxX - size.width, y: frame.minY - size.height - 6)
        if let visible = screen?.visibleFrame, origin.y < visible.minY { origin.y = frame.maxY + 6 }
        editBar.setFrameOrigin(origin)
    }

    // MARK: - 우클릭 메뉴

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            return item
        }
        menu.addItem(add(isEditingMarkup ? L("표시 편집 끝내기", "Finish Markup") : L("표시 편집 (사각형·화살표·펜)", "Markup (box, arrow, pen)"), isEditingMarkup ? #selector(finishEditingFromMenu) : #selector(beginEditing)))
        menu.addItem(.separator())
        menu.addItem(add(L("복사", "Copy"), #selector(copyImage)))
        menu.addItem(add(L("저장…", "Save…"), #selector(saveImage)))
        menu.addItem(add(L("텍스트 추출", "Extract Text"), #selector(extractText)))
        menu.addItem(.separator())
        let opacity = NSMenuItem(title: L("투명도", "Opacity"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for percent in [100, 80, 60, 40] {
            let item = add("\(percent)%", #selector(setOpacity(_:)), tag: percent)
            item.state = abs(alphaValue * 100 - CGFloat(percent)) < 1 ? .on : .off
            sub.addItem(item)
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(add(L("원래 크기", "Actual Size"), #selector(resetZoom)))
        menu.addItem(add(L("클릭 통과 (핀 아래 창 쓰기)", "Click-Through (use the window below)"), #selector(turnOnClickThrough)))
        menu.addItem(.separator())
        menu.addItem(add(L("닫기", "Close"), #selector(closeFromMenu)))
        return menu
    }

    @objc private func finishEditingFromMenu() { endEditing() }

    func copyFromKeyboard() { copyImage() }

    @objc private func copyImage() {
        PasteboardWriter.copy(composite, scale: scale, origin: .capture)
        Toast.show(L("이미지를 복사했습니다", "Image copied"))
    }

    @objc func saveImage() {
        PinPanel.save(composite)
    }

    /// 저장 창. 캡처 편집의 "저장"에서도 쓴다.
    static func save(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "PolyMac \(stamp.string(from: Date())).png"
        panel.level = .modalPanel
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { return }
            do {
                try data.write(to: url)
                MainActor.assumeIsolated { Toast.show(L("저장했습니다: \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)")) }
            } catch {
                MainActor.assumeIsolated { Toast.show(L("저장 실패: \(error.localizedDescription)", "Save failed: \(error.localizedDescription)")) }
            }
        }
    }

    @objc private func extractText() {
        let image = image // 표시가 글자 인식을 방해하지 않게 원본으로
        Task { @MainActor in await OCRRunner.recognizeAndCopy(image) }
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        alphaValue = CGFloat(sender.tag) / 100
    }

    @objc private func resetZoom() {
        zoom = 1
        resize(to: baseSize)
    }

    @objc private func closeFromMenu() {
        closePin()
    }
}

private final class PinCanvasView: NSView, NSDraggingSource {
    weak var pin: PinPanel?
    private let image: CGImage
    private var drawing: Annotation?
    private var textInput: AnnotationTextInput?

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let pin else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: bounds)
        ctx.saveGState()
        ctx.scaleBy(x: pin.displayFactor, y: pin.displayFactor)
        AnnotationRenderer.draw(pin.annotations + (drawing.map { [$0] } ?? []), in: ctx,
                                source: .init(image: image, scale: pin.scale))
        ctx.restoreGState()
    }

    override func resetCursorRects() {
        if pin?.isEditingMarkup == true { addCursorRect(bounds, cursor: .crosshair) }
    }

    private func basePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let factor = pin?.displayFactor ?? 1
        return CGPoint(x: p.x / factor, y: p.y / factor)
    }

    override var acceptsFirstResponder: Bool { true }

    /// 기본 메뉴(편집)의 ⌘C가 먼저 찾는 동작
    @objc func copy(_ sender: Any?) {
        pin?.copyFromKeyboard()
    }

    /// 핀을 클릭해 앞으로 가져온 상태에서: Esc·⌫·⌦ 닫기, ⌘C 복사
    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53, 51, 117:
            if pin?.isEditingMarkup == true, event.keyCode == 53 { pin?.endEditing() } else { pin?.closePin() }
        default:
            if event.modifierFlags.contains(.command), event.latinKey == "c" {
                pin?.copyFromKeyboard()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if let input = textInput, input.isActive {
            input.commit()
            return
        }
        if let pin, let tool = pin.markupBar?.selectedTool {
            let color = pin.markupBar?.color ?? .systemRed
            if tool == .text {
                let anchor = basePoint(event)
                textInput = AnnotationTextInput(in: self, at: convert(event.locationInWindow, from: nil), color: color,
                                                zoom: pin.displayFactor) { [weak self] text in
                    guard let self else { return }
                    var a = Annotation(tool: .text, start: anchor, color: color)
                    a.text = text
                    if a.isMeaningful { self.pin?.annotations.append(a) }
                    self.textInput = nil
                    self.window?.makeFirstResponder(self)
                    self.needsDisplay = true
                }
                return
            }
            drawing = Annotation(tool: tool, start: basePoint(event), color: color)
            if tool == .number { drawing?.number = Annotation.nextNumber(after: pin.annotations) }
            return
        }
        if event.clickCount == 2 {
            pin?.closePin()
        } else if event.modifierFlags.contains(.command) {
            beginExport(with: event)
        } else {
            window?.performDrag(with: event)
        }
    }

    /// ⌘드래그: 표시까지 합친 PNG 파일로 Finder·메신저·메일 등에 넣는다
    private func beginExport(with event: NSEvent) {
        guard let pin else { return }
        let url: URL
        do {
            url = try PinExport.write(pin.composite)
        } catch {
            Toast.show(L("끌어 넣을 파일을 만들지 못했습니다", "Could not prepare the file to drag"), content: error.localizedDescription)
            return
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: pin.composite, size: bounds.size)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    override func mouseDragged(with event: NSEvent) {
        guard drawing != nil else { return }
        drawing?.extend(to: basePoint(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let finished = drawing else { return }
        if finished.isMeaningful { pin?.annotations.append(finished) }
        drawing = nil
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        if event.modifierFlags.contains(.option) {
            pin?.adjustOpacity(by: delta)
        } else {
            pin?.zoom(by: delta)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { pin?.makeMenu() }

    override var mouseDownCanMoveWindow: Bool { false }

    /// 다른 앱을 쓰다가 핀을 처음 누를 때도 바로 옮기기·그리기가 되게 (없으면 첫 클릭은 창을 앞으로 가져오는 데만 쓰인다)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
