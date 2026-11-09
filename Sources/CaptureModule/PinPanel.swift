import AppKit
import OCRModule
import PolyMacCore
import UniformTypeIdentifiers
import VisionKit
import os

/// 화면 위에 떠 있는 캡처(핀). 드래그로 이동, ⌘드래그로 다른 앱에 PNG로 넣기, 스크롤로 확대/축소, ⌥+스크롤로 투명도, 더블클릭으로 닫기.
/// 표시(사각형·화살표·펜)는 이미지에 굽지 않고 따로 들고 있어 우클릭 › 표시 편집으로 다시 고칠 수 있다.
/// 우클릭 › 텍스트 선택: 라이브 텍스트(VisionKit, 기기 안에서만)로 핀 위 글자를 드래그해 골라 복사한다.
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
    private var liveText: ImageAnalysisOverlayView?
    private static let analyzer = ImageAnalyzer()
    static let logger = Logger(subsystem: "dev.polymac", category: "capture")

    var isEditingMarkup: Bool { markupBar != nil }
    var isSelectingText: Bool { liveText != nil }

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
        endTextSelection()
        orderOut(nil)
        PinPanel.open.remove(self)
    }

    func zoom(by delta: CGFloat) {
        zoom(times: delta > 0 ? 1.06 : 1 / 1.06)
    }

    /// 핀치: 손가락 벌린 만큼 (가운데 기준)
    func zoom(times factor: CGFloat) {
        zoom = min(max(zoom * factor, PinResize.minZoom), PinResize.maxZoom)
        resize(to: NSSize(width: baseSize.width * zoom, height: baseSize.height * zoom))
    }

    var zoomLevel: CGFloat { zoom }

    /// 가장자리·모서리 끌기 (PinResize)
    func resize(from start: NSRect, edges: PinResize.Edges, dx: CGFloat, dy: CGFloat) {
        let (rect, factor) = PinResize.frame(from: start, base: baseSize, edges: edges, dx: dx, dy: dy)
        zoom = factor
        setFrame(rect, display: true)
        placeEditBar()
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
        endTextSelection()
        let bar = AnnotationToolbar(output: false)
        bar.select(.rectangle)
        bar.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .undo:
                (self.contentView as? PinCanvasView)?.undoMarkup()
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
        (contentView as? PinCanvasView)?.finishTextEditing()
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

    // MARK: - 텍스트 선택 (라이브 텍스트)

    /// 표시를 뺀 원본에서 글자를 찾아 핀 위에 고를 수 있게 덮는다. 켜 있는 동안 핀은 끌어 옮기지 않는다 (드래그 = 글자 고르기).
    @objc func beginTextSelection() {
        guard liveText == nil else { return }
        endEditing()
        guard ImageAnalyzer.isSupported else {
            Toast.show(L("이 Mac에서는 라이브 텍스트를 쓸 수 없습니다", "Live Text is not available on this Mac"))
            return
        }
        let image = image
        Task { @MainActor [weak self] in
            var configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            configuration.locales = ["ko-KR", "en-US"]
            let analysis: ImageAnalysis
            do {
                analysis = try await PinPanel.analyzer.analyze(image, orientation: .up, configuration: configuration)
            } catch {
                PinPanel.logger.error("live text failed: \(error.localizedDescription, privacy: .public)")
                Toast.show(L("글자를 읽지 못했습니다: \(error.localizedDescription)", "Could not read text: \(error.localizedDescription)"))
                return
            }
            guard let self, self.isVisible, self.liveText == nil, let view = self.contentView else { return }
            guard analysis.hasResults(for: .text) || analysis.hasResults(for: .machineReadableCode) else {
                Toast.show(L("핀에서 글자를 찾지 못했습니다", "No text found on the pin"))
                return
            }
            let overlay = ImageAnalysisOverlayView(frame: view.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.preferredInteractionTypes = .textSelection
            overlay.delegate = self
            overlay.analysis = analysis
            view.addSubview(overlay)
            self.liveText = overlay
            view.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
            view.layer?.borderWidth = 2
            self.makeKey()
            overlay.selectableItemsHighlighted = true
            PinPanel.logger.info("live text on pin")
            Toast.show(L("글자를 드래그해 고른 뒤 ⌘C", "Drag over text, then ⌘C"),
                       content: L("끝내기: Esc 또는 우클릭 › 텍스트 선택 끝내기", "Finish: Esc or right-click › Finish Text Selection"), duration: 3)
        }
    }

    @objc func endTextSelection() {
        guard let liveText else { return }
        liveText.removeFromSuperview()
        self.liveText = nil
        setClickThrough(false) // 테두리를 원래대로
    }

    /// 고른 글자가 있으면 그것을, 없으면 nil (⌘C가 이미지 복사로 간다)
    var selectedText: String? {
        guard let text = liveText?.selectedText, !text.isEmpty else { return nil }
        return text
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
        menu.addItem(add(isSelectingText ? L("텍스트 선택 끝내기", "Finish Text Selection") : L("텍스트 선택 (드래그로 고르기)", "Select Text (drag over it)"),
                         isSelectingText ? #selector(endTextSelection) : #selector(beginTextSelection)))
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

    func copyFromKeyboard() {
        if let text = selectedText {
            PasteboardWriter.copy(text.precomposedStringWithCanonicalMapping, origin: .ocr)
            Toast.show(L("고른 글자를 복사했습니다", "Selected text copied"))
        } else {
            copyImage()
        }
    }

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
    private lazy var textEditor = AnnotationTextEditor(view: self, get: { [unowned self] in pin?.annotations ?? [] }, set: { [unowned self] in pin?.annotations = $0 },
                                                       toView: { [unowned self] in
                                                           let factor = pin?.displayFactor ?? 1
                                                           return NSPoint(x: $0.x * factor, y: $0.y * factor)
                                                       }, zoom: { [unowned self] in pin?.displayFactor ?? 1 })
    /// 가장자리 끌기로 크기 바꾸는 중: 잡은 가장자리, 시작 틀, 시작 마우스 위치(화면 좌표)
    private var resizing: (edges: PinResize.Edges, frame: NSRect, mouse: NSPoint)?

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
        if pin.isEditingMarkup { textEditor.draw(in: ctx) }
        ctx.restoreGState()
    }

    func finishTextEditing() {
        textEditor.commitInput()
        textEditor.select(nil)
    }

    func undoMarkup() {
        if textEditor.undo() { return }
        if pin?.annotations.isEmpty == false { pin?.annotations.removeLast() }
    }

    override func resetCursorRects() {
        if pin?.isEditingMarkup == true { addCursorRect(bounds, cursor: .crosshair) }
    }

    // 핀은 앞으로 오지 않은(키 창이 아닌) 상태가 대부분이라 커서 영역 대신 항상 받는 추적 영역으로 커서를 바꾼다
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        super.updateTrackingAreas()
    }

    private func resizeEdges(_ event: NSEvent) -> PinResize.Edges {
        guard pin?.isEditingMarkup != true else { return PinResize.Edges() }
        return PinResize.edges(at: convert(event.locationInWindow, from: nil), in: bounds.size)
    }

    override func mouseMoved(with event: NSEvent) {
        if let pin, pin.isEditingMarkup {
            let tool = pin.markupBar?.selectedTool
            let point = basePoint(event)
            textEditor.updateHover(at: tool == .text ? point : nil, color: pin.markupBar?.color ?? .systemRed)
            if tool == nil || tool == .text {
                (textEditor.cursor(at: point) ?? (tool == .text ? .iBeam : .arrow)).set()
            }
            return
        }
        guard resizing == nil else { return }
        let edges = resizeEdges(event)
        (edges.isEmpty ? NSCursor.arrow : PinResize.cursor(for: edges)).set()
    }

    override func mouseExited(with event: NSEvent) {
        if resizing == nil, pin?.isEditingMarkup != true { NSCursor.arrow.set() }
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
        case 123...126 where textEditor.selected != nil:
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let move = [123: (-step, 0), 124: (step, 0), 125: (0, -step), 126: (0, step)][Int(event.keyCode)] ?? (0, 0)
            _ = textEditor.nudge(dx: move.0, dy: move.1)
        case 53 where textEditor.selected != nil:
            textEditor.select(nil)
        case 51 where textEditor.deleteSelected(), 117 where textEditor.deleteSelected():
            break
        case 53, 51, 117:
            if pin?.isEditingMarkup == true, event.keyCode == 53 { pin?.endEditing() }
            else if pin?.isSelectingText == true, event.keyCode == 53 { pin?.endTextSelection() }
            else { pin?.closePin() }
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
        if textEditor.commitInput() { return }
        if let pin, pin.isEditingMarkup {
            let tool = pin.markupBar?.selectedTool
            let color = pin.markupBar?.color ?? .systemRed
            if tool == nil || tool == .text {
                switch textEditor.press(at: basePoint(event), clickCount: event.clickCount) {
                case .edit:
                    textEditor.editSelected()
                    return
                case .grabbed:
                    return
                case .none:
                    break
                }
            }
            if tool == .text || (tool == nil && event.clickCount == 2) {
                textEditor.beginText(at: basePoint(event), color: color)
                return
            }
        }
        if let pin, let tool = pin.markupBar?.selectedTool {
            let color = pin.markupBar?.color ?? .systemRed
            textEditor.select(nil)
            drawing = Annotation(tool: tool, start: basePoint(event), color: color)
            if tool == .number { drawing?.number = Annotation.nextNumber(after: pin.annotations) }
            return
        }
        let edges = resizeEdges(event)
        if !edges.isEmpty, let window {
            resizing = (edges, window.frame, NSEvent.mouseLocation)
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
        if let resizing {
            let mouse = NSEvent.mouseLocation
            pin?.resize(from: resizing.frame, edges: resizing.edges, dx: mouse.x - resizing.mouse.x, dy: mouse.y - resizing.mouse.y)
            return
        }
        if textEditor.selected != nil {
            textEditor.dragged(to: basePoint(event))
            return
        }
        guard drawing != nil else { return }
        drawing?.extend(to: basePoint(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizing != nil {
            resizing = nil
            if let pin { PinPanel.logger.info("pin resized zoom=\(pin.zoomLevel, privacy: .public)") }
            mouseMoved(with: event)
            return
        }
        textEditor.released()
        guard let finished = drawing else { return }
        if finished.isMeaningful {
            textEditor.willChange()
            pin?.annotations.append(finished)
        }
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

    /// 트랙패드 두 손가락 벌리기·오므리기
    override func magnify(with event: NSEvent) {
        pin?.zoom(times: 1 + event.magnification)
    }

    override func menu(for event: NSEvent) -> NSMenu? { pin?.makeMenu() }

    override var mouseDownCanMoveWindow: Bool { false }

    /// 다른 앱을 쓰다가 핀을 처음 누를 때도 바로 옮기기·그리기가 되게 (없으면 첫 클릭은 창을 앞으로 가져오는 데만 쓰인다)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 라이브 텍스트의 우클릭 메뉴(복사·찾아보기 등) 아래에 핀 메뉴를 붙인다
extension PinPanel: ImageAnalysisOverlayViewDelegate {
    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu {
        let pinMenu = makeMenu()
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for item in pinMenu.items {
            pinMenu.removeItem(item)
            menu.addItem(item)
        }
        return menu
    }
}
