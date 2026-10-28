import AppKit
import PolyMacL10n

/// 캡처 배경 — 찍어 둔 화면을 레이어로 한 번만 올려 둔다 (마우스를 움직일 때마다 다시 그리지 않음).
final class CaptureBackgroundView: NSView {
    init(frame: NSRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 캡처 영역 선택·편집 화면 (모니터마다 하나). 배경 위에 투명하게 겹쳐
/// 어둡게 덮기, 선택 영역, 돋보기, 크기, 단축키 안내, 표시(사각형·화살표·펜)를 그린다.
final class SelectionView: NSView {
    struct Outcome {
        let image: CGImage
        let rect: NSRect
        let annotations: [Annotation]
        let action: CaptureAction?
    }

    private enum Handle: CaseIterable {
        case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left
    }

    private enum Drag {
        case creating(start: NSPoint)
        case moving(last: NSPoint)
        case resizing(Handle, original: NSRect)
        case annotating
    }

    private let image: CGImage
    private let scale: CGFloat
    private let editing: Bool
    /// 앞에 있는 창부터 (이 화면 기준 좌표)
    private let windowRects: [NSRect]

    private var selection: NSRect = .zero
    /// 영역을 확정하고 편집 중인 단계
    private var isSelected = false
    private var drag: Drag?
    private var hoverRect: NSRect?
    private var mouse: NSPoint?
    private var showsHex = false
    private var colorCopiedAt: Date?
    private var annotations: [Annotation] = []
    private var drawing: Annotation?
    private var toolbar: AnnotationToolbar?
    private var textInput: AnnotationTextInput?
    private var lastExtent: NSRect?

    var onFinish: ((Outcome?) -> Void)?
    var onActivity: (() -> Void)?
    var onSelectionStarted: (() -> Void)?

    init(frame: NSRect, image: CGImage, scale: CGFloat, editing: Bool, windowRects: [NSRect]) {
        self.image = image
        self.scale = scale
        self.editing = editing
        self.windowRects = windowRects
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let p = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        if bounds.contains(p) { mouse = p }
        updateHover()
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    func reset() {
        selection = .zero
        isSelected = false
        drag = nil
        annotations.removeAll()
        drawing = nil
        toolbar?.removeFromSuperview()
        toolbar = nil
        needsDisplay = true
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clip(to: dirtyRect)

        // 1) 선택(또는 마우스 아래 창) 바깥을 어둡게
        let hole = selection.width > 0 ? selection : hoverRect
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole { dim.addRect(hole) }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        ctx.fillPath(using: .evenOdd)

        if selection.width > 0 {
            drawSelection(ctx)
        } else if let hover = hoverRect {
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(hover.insetBy(dx: 1.5, dy: 1.5))
            pill(L("\(Int(hover.width * scale)) × \(Int(hover.height * scale)) px  ·  클릭하면 이 창 선택", "\(Int(hover.width * scale)) × \(Int(hover.height * scale)) px  ·  click to select this window"),
                 at: NSPoint(x: hover.minX + 6, y: min(hover.maxY - 28, bounds.maxY - 28)), ctx)
        } else if let mouse {
            drawCrosshair(at: mouse, ctx)
        }

        if showsMagnifier, let mouse { drawMagnifier(at: mouse, ctx) }
        drawHints(ctx)
    }

    private var showsMagnifier: Bool {
        guard mouse != nil else { return false }
        if case .resizing = drag { return true }
        if case .creating = drag { return true }
        return !isSelected
    }

    private func drawCrosshair(at p: NSPoint, _ ctx: CGContext) {
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: bounds.minX, y: p.y)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: bounds.minY)); ctx.addLine(to: CGPoint(x: p.x, y: bounds.maxY))
        ctx.strokePath()
    }

    private func drawSelection(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: selection)
        ctx.translateBy(x: selection.minX, y: selection.minY)
        AnnotationRenderer.draw(annotations + (drawing.map { [$0] } ?? []), in: ctx,
                                source: .init(image: image, scale: scale, origin: selection.origin))
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(selection.insetBy(dx: 0.75, dy: 0.75))

        if isSelected, editing {
            for handle in Handle.allCases {
                let r = handleRect(handle)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(r)
            }
        }
        let label = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded())) px"
        let above = selection.maxY + 30 < bounds.maxY
        pill(label, at: NSPoint(x: selection.minX, y: above ? selection.maxY + 6 : selection.maxY - 28), ctx)
    }

    /// 커서 옆 돋보기: 15×15 픽셀을 8배로, 아래에 좌표와 색상
    private func drawMagnifier(at p: NSPoint, _ ctx: CGContext) {
        let frame = magnifierFrame(at: p)
        let n = 15, cell: CGFloat = 8
        let box = NSRect(x: frame.minX, y: frame.maxY - CGFloat(n) * cell, width: CGFloat(n) * cell, height: CGFloat(n) * cell)
        let info = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - box.height)
        let (px, py) = pixel(at: p)

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(box)
        let source = CGRect(x: px - n / 2, y: py - n / 2, width: n, height: n)
        let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if !visible.isNull, let zoom = image.cropping(to: visible) {
            ctx.interpolationQuality = .none
            let dx = (visible.minX - source.minX) * cell, dyTop = (visible.minY - source.minY) * cell
            ctx.draw(zoom, in: CGRect(x: box.minX + dx, y: box.maxY - dyTop - visible.height * cell,
                                      width: visible.width * cell, height: visible.height * cell))
        }
        // 가운데 픽셀 십자선
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: box.minX + CGFloat(n / 2) * cell, y: box.minY, width: cell, height: box.height))
        ctx.fill(CGRect(x: box.minX, y: box.maxY - CGFloat(n / 2 + 1) * cell, width: box.width, height: cell))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: box.minX + CGFloat(n / 2) * cell, y: box.maxY - CGFloat(n / 2 + 1) * cell, width: cell, height: cell))
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        ctx.fill(info)
        ctx.restoreGState()

        let rgb = color(atPixel: px, py)
        let colorText: String
        if let rgb {
            colorText = showsHex ? String(format: "#%02X%02X%02X", rgb.0, rgb.1, rgb.2) : "\(rgb.0), \(rgb.1), \(rgb.2)"
            ctx.setFillColor(CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1))
            let swatch = CGRect(x: info.minX + 8, y: info.maxY - 36, width: 12, height: 12)
            ctx.fill(swatch)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(swatch)
        } else {
            colorText = "-"
        }
        let copied = colorCopiedAt.map { Date().timeIntervalSince($0) < 1.2 } ?? false
        text("(\(Int(p.x)), \(Int(bounds.height - p.y)))", at: NSPoint(x: info.minX + 8, y: info.maxY - 20), size: 11)
        text(colorText, at: NSPoint(x: info.minX + 26, y: info.maxY - 38), size: 11)
        text(copied ? L("✓ 색상을 복사했습니다", "✓ Color copied") : L("C 색상 복사 · ⇧ RGB/HEX", "C copy color · ⇧ RGB/HEX"), at: NSPoint(x: info.minX + 8, y: info.minY + 6), size: 10,
             color: copied ? .systemGreen : NSColor.white.withAlphaComponent(0.7))
    }

    private func magnifierFrame(at p: NSPoint) -> NSRect {
        let size = NSSize(width: 120, height: 120 + 60)
        var origin = NSPoint(x: p.x + 20, y: p.y - 20 - size.height)
        if origin.x + size.width > bounds.maxX - 4 { origin.x = p.x - 20 - size.width }
        if origin.y < bounds.minY + 4 { origin.y = p.y + 20 }
        return NSRect(origin: origin, size: size)
    }

    /// 왼쪽 아래 단축키 안내 — 단계마다 내용이 바뀐다
    private func drawHints(_ ctx: CGContext) {
        let rows: [(String, String)]
        if isSelected {
            rows = [
                (L("드래그", "Drag"), L("안쪽: 이동 · 테두리: 크기 조절", "inside: move · edge: resize")),
                ("← ↑ ↓ →", L("1px 이동 (⇧ 10px)", "move 1px (⇧ 10px)")),
                ("R A P", L("사각형 · 화살표 · 펜", "box · arrow · pen")),
                ("E M N", L("글자 · 모자이크 · 번호", "text · mosaic · number")),
                ("1 ~ 8", L("색상 (1 빨강)", "color (1 red)")),
                ("⌘Z", L("표시 되돌리기", "undo markup")),
                ("T", L("텍스트 추출", "extract text")),
                ("F", L("화면에 고정", "pin to screen")),
                ("⌘S", L("파일로 저장", "save to file")),
                ("↩  ⌘C", L("복사하고 닫기", "copy and close")),
                ("Esc", L("취소", "cancel")),
            ]
        } else {
            rows = [
                (L("드래그", "Drag"), L("영역 선택", "select area")),
                (L("클릭", "Click"), L("마우스 아래 창 선택", "select window under cursor")),
                ("⌘A", L("화면 전체", "whole screen")),
                ("C", L("커서 위치 색상 복사", "copy color under cursor")),
                ("⇧", L("RGB / HEX 바꾸기", "toggle RGB / HEX")),
                ("Esc", L("취소", "cancel")),
            ]
        }
        let rowHeight: CGFloat = 22
        let panel = NSRect(x: 16, y: 16, width: 270, height: CGFloat(rows.count) * rowHeight + 38)
        guard panel.intersects(ctx.boundingBoxOfClipPath) else { return }
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: panel, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        text(L("PolyMac 캡처", "PolyMac Capture"), at: NSPoint(x: panel.minX + 12, y: panel.maxY - 26), size: 13, weight: .semibold)
        for (i, row) in rows.enumerated() {
            let y = panel.maxY - 52 - CGFloat(i) * rowHeight
            keycap(row.0, at: NSPoint(x: panel.minX + 12, y: y), ctx)
            text(row.1, at: NSPoint(x: panel.minX + 92, y: y + 2), size: 12)
        }
    }

    private func keycap(_ key: String, at p: NSPoint, _ ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let size = (key as NSString).size(withAttributes: attrs)
        let r = NSRect(x: p.x, y: p.y, width: max(size.width + 10, 20), height: 18)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        (key as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.minY + 2), withAttributes: attrs)
    }

    private func pill(_ string: String, at p: NSPoint, _ ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let size = (string as NSString).size(withAttributes: attrs)
        let r = NSRect(x: max(p.x, 4), y: p.y, width: size.width + 14, height: 22)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.fillPath()
        (string as NSString).draw(at: NSPoint(x: r.minX + 7, y: r.minY + 3), withAttributes: attrs)
    }

    private func text(_ string: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) {
        (string as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    /// 바뀐 부분만 다시 그린다 (전체 화면을 매번 그리지 않음)
    private func refresh() {
        var extent: NSRect?
        func add(_ r: NSRect?) {
            guard let r, r.width > 0, r.height > 0 else { return }
            extent = extent.map { $0.union(r) } ?? r
        }
        add(selection.width > 0 ? selection.insetBy(dx: -40, dy: -40) : nil)
        add(hoverRect?.insetBy(dx: -40, dy: -40))
        if showsMagnifier, let mouse { add(magnifierFrame(at: mouse).insetBy(dx: -4, dy: -4)) }
        if selection.width == 0, hoverRect == nil, mouse != nil { extent = bounds } // 십자선은 화면 끝까지
        var dirty = lastExtent
        if let extent { dirty = dirty.map { $0.union(extent) } ?? extent }
        if let dirty { setNeedsDisplay(dirty) }
        lastExtent = extent
    }

    // MARK: - 좌표·색상

    private func pixel(at p: NSPoint) -> (Int, Int) {
        (Int(p.x * scale), Int((bounds.height - p.y) * scale))
    }

    private func color(atPixel x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let one = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return ok ? (bytes[0], bytes[1], bytes[2]) : nil
    }

    private func copyColor() {
        guard let mouse else { return }
        let (px, py) = pixel(at: mouse)
        guard let rgb = color(atPixel: px, py) else { return }
        let value = showsHex ? String(format: "#%02X%02X%02X", rgb.0, rgb.1, rgb.2) : "\(rgb.0), \(rgb.1), \(rgb.2)"
        PasteboardWriter.copy(value)
        colorCopiedAt = Date()
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - 핸들

    private func handlePoint(_ h: Handle) -> NSPoint {
        let r = selection
        switch h {
        case .bottomLeft: return NSPoint(x: r.minX, y: r.minY)
        case .bottom: return NSPoint(x: r.midX, y: r.minY)
        case .bottomRight: return NSPoint(x: r.maxX, y: r.minY)
        case .right: return NSPoint(x: r.maxX, y: r.midY)
        case .topRight: return NSPoint(x: r.maxX, y: r.maxY)
        case .top: return NSPoint(x: r.midX, y: r.maxY)
        case .topLeft: return NSPoint(x: r.minX, y: r.maxY)
        case .left: return NSPoint(x: r.minX, y: r.midY)
        }
    }

    private func handleRect(_ h: Handle) -> NSRect {
        let c = handlePoint(h)
        return NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
    }

    /// 모서리 근처면 모서리, 아니면 테두리 어디든 그 변 — 작은 핸들 점만이 아니라 선 전체를 잡을 수 있게
    private func handle(at p: NSPoint) -> Handle? {
        let r = selection, edge: CGFloat = 7, corner: CGFloat = 12
        guard r.insetBy(dx: -edge, dy: -edge).contains(p) else { return nil }
        let nearLeft = abs(p.x - r.minX) <= edge, nearRight = abs(p.x - r.maxX) <= edge
        let nearBottom = abs(p.y - r.minY) <= edge, nearTop = abs(p.y - r.maxY) <= edge
        let cornerLeft = abs(p.x - r.minX) <= corner, cornerRight = abs(p.x - r.maxX) <= corner
        let cornerBottom = abs(p.y - r.minY) <= corner, cornerTop = abs(p.y - r.maxY) <= corner
        if cornerLeft && cornerBottom { return .bottomLeft }
        if cornerRight && cornerBottom { return .bottomRight }
        if cornerLeft && cornerTop { return .topLeft }
        if cornerRight && cornerTop { return .topRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearTop { return .top }
        return nil
    }

    private func resized(_ original: NSRect, _ h: Handle, to p: NSPoint) -> NSRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        switch h {
        case .left, .topLeft, .bottomLeft: minX = p.x
        case .right, .topRight, .bottomRight: maxX = p.x
        default: break
        }
        switch h {
        case .bottom, .bottomLeft, .bottomRight: minY = p.y
        case .top, .topLeft, .topRight: maxY = p.y
        default: break
        }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: max(abs(maxX - minX), 4), height: max(abs(maxY - minY), 4))
            .intersection(bounds)
    }

    /// 선택 영역 원점이 바뀌어도 표시는 화면 내용에 붙어 있게
    private func setSelection(_ new: NSRect) {
        let dx = new.minX - selection.minX, dy = new.minY - selection.minY
        if (dx != 0 || dy != 0), !annotations.isEmpty {
            annotations = annotations.map { a in
                var a = a
                a.points = a.points.map { CGPoint(x: $0.x - dx, y: $0.y - dy) }
                return a
            }
        }
        selection = new
        placeToolbar()
    }

    // MARK: - 마우스

    private func updateHover() {
        let next: NSRect? = (selection.width > 0 || drag != nil || isSelected) ? nil : mouse.flatMap { m in windowRects.first { $0.contains(m) } }
        if next != hoverRect { hoverRect = next }
    }

    private func updateCursor(at p: NSPoint) {
        guard isSelected, editing else { NSCursor.crosshair.set(); return }
        if toolbar?.selectedTool != nil { NSCursor.crosshair.set(); return }
        if let h = handle(at: p) {
            switch h {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .topLeft, .bottomRight:
                if #available(macOS 15, *) { NSCursor.frameResize(position: .topLeft, directions: .all).set() } else { NSCursor.crosshair.set() }
            case .topRight, .bottomLeft:
                if #available(macOS 15, *) { NSCursor.frameResize(position: .topRight, directions: .all).set() } else { NSCursor.crosshair.set() }
            }
        } else if selection.contains(p) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        updateHover()
        updateCursor(at: p)
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        hoverRect = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onActivity?()
        // 다른 모니터를 눌렀으면 그 화면이 키 입력을 받게
        window?.makeKey()
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        if isSelected {
            // 입력 중인 글자가 있으면 다른 곳을 누를 때 확정만 한다
            if let input = textInput, input.isActive {
                input.commit()
                return
            }
            if let tool = toolbar?.selectedTool {
                guard selection.contains(p) else { return }
                if tool == .text {
                    beginText(at: p)
                    return
                }
                drawing = Annotation(tool: tool, start: local(p), color: toolbar?.color ?? .systemRed)
                if tool == .number { drawing?.number = Annotation.nextNumber(after: annotations) }
                drag = .annotating
                return
            }
            if let h = handle(at: p) {
                drag = .resizing(h, original: selection)
                return
            }
            if selection.contains(p) {
                drag = .moving(last: p)
                NSCursor.closedHand.set()
                return
            }
            // 표시를 그린 뒤에는 바깥을 눌러도 영역을 잃지 않게
            guard annotations.isEmpty else { return }
            reset()
        }
        drag = .creating(start: p)
        selection = .zero
        onSelectionStarted?()
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        switch drag {
        case .creating(let start):
            hoverRect = nil
            selection = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y)).intersection(bounds)
        case .moving(let last):
            var moved = selection.offsetBy(dx: p.x - last.x, dy: p.y - last.y)
            moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
            setSelection(moved)
            drag = .moving(last: p)
        case .resizing(let h, let original):
            setSelection(resized(original, h, to: p))
        case .annotating:
            let clamped = NSPoint(x: min(max(p.x, selection.minX), selection.maxX), y: min(max(p.y, selection.minY), selection.maxY))
            drawing?.extend(to: local(clamped))
        case nil:
            break
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        onActivity?()
        defer {
            drag = nil
            needsDisplay = true
        }
        switch drag {
        case .annotating:
            if let finished = drawing, finished.isMeaningful { annotations.append(finished) }
            drawing = nil
        case .creating:
            if selection.width < 4 || selection.height < 4 {
                // 끌지 않고 클릭만 했으면 마우스 아래 창 크기로
                guard let hover = hoverRect else {
                    selection = .zero
                    return
                }
                selection = hover
            }
            hoverRect = nil
            confirmSelection()
        case .moving:
            if let mouse { updateCursor(at: mouse) }
        default:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }

    private func confirmSelection() {
        if editing {
            isSelected = true
            showToolbar()
        } else {
            complete(nil)
        }
    }

    // MARK: - 키보드

    // 기본 메뉴(편집)의 ⌘C·⌘A·⌘Z가 먼저 이 동작들을 찾으므로 같은 일을 하게 연결해 둔다

    @objc func copy(_ sender: Any?) {
        if isSelected { complete(.copy) }
    }

    override func selectAll(_ sender: Any?) {
        reset()
        selection = bounds
        confirmSelection()
    }

    @objc func undo(_ sender: Any?) {
        undoAnnotation()
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
        if event.keyCode == 53 { onFinish?(nil); return } // Esc
        let cmd = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if cmd, key == "a" {
            reset()
            selection = bounds
            confirmSelection()
            return
        }
        if !cmd, key == "c" { copyColor(); return }
        guard isSelected else { return }

        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case 123: nudge(-step, 0); return
        case 124: nudge(step, 0); return
        case 125: nudge(0, -step); return
        case 126: nudge(0, step); return
        default: break
        }
        if !cmd, let key, let n = Int(key), (1...AnnotationToolbar.palette.count).contains(n) {
            toolbar?.selectColor(n - 1)
            return
        }
        switch (key, cmd) {
        case ("z", true): undoAnnotation()
        case ("c", true): complete(.copy)
        case ("s", true): complete(.save)
        case ("\r", _): complete(.copy)
        case ("r", false): pick(.rectangle)
        case ("a", false): pick(.arrow)
        case ("p", false): pick(.pen)
        case ("e", false): pick(.text)
        case ("m", false): pick(.mosaic)
        case ("n", false): pick(.number)
        case ("t", false): complete(.ocr)
        case ("f", false): complete(.pin)
        default: break
        }
    }

    /// ⇧를 누를 때마다 RGB ↔ HEX
    override func flagsChanged(with event: NSEvent) {
        if event.keyCode == 56 || event.keyCode == 60, event.modifierFlags.contains(.shift) {
            showsHex.toggle()
            refresh()
        }
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        var moved = selection.offsetBy(dx: dx, dy: dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        setSelection(moved)
        needsDisplay = true
    }

    // MARK: - 도구 막대

    private func showToolbar() {
        let bar = AnnotationToolbar(output: true)
        bar.onAction = { [weak self] action in
            guard let self else { return }
            self.onActivity?()
            switch action {
            case .tool: if let mouse = self.mouse { self.updateCursor(at: mouse) }
            case .undo: self.undoAnnotation()
            case .ocr: self.complete(.ocr)
            case .pin: self.complete(.pin)
            case .save: self.complete(.save)
            case .copy, .done: self.complete(.copy)
            case .cancel: self.onFinish?(nil)
            }
        }
        addSubview(bar)
        toolbar = bar
        placeToolbar()
        needsDisplay = true
    }

    private func placeToolbar() {
        guard let bar = toolbar else { return }
        let size = bar.frame.size
        var origin = NSPoint(x: selection.maxX - size.width, y: selection.minY - size.height - 8)
        if origin.y < 8 { origin.y = selection.maxY + 34 }                              // 아래 공간이 없으면 위로 (크기 표시 위)
        if origin.y + size.height > bounds.maxY - 8 { origin.y = selection.minY + 8 }  // 위도 없으면 영역 안쪽
        origin.x = min(max(origin.x, 8), bounds.maxX - size.width - 8)
        bar.setFrameOrigin(origin)
    }

    private func pick(_ tool: AnnotationTool) {
        toolbar?.select(toolbar?.selectedTool == tool ? nil : tool)
    }

    /// 글자 도구: 누른 자리에 입력 칸을 띄우고, 확정하면 표시로 남긴다
    private func beginText(at p: NSPoint) {
        let color = toolbar?.color ?? .systemRed
        let anchor = local(p)
        textInput = AnnotationTextInput(in: self, at: p, color: color) { [weak self] text in
            guard let self else { return }
            var a = Annotation(tool: .text, start: anchor, color: color)
            a.text = text
            if a.isMeaningful { self.annotations.append(a) }
            self.textInput = nil
            self.window?.makeFirstResponder(self)
            self.needsDisplay = true
        }
    }

    private func undoAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    private func local(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x - selection.minX, y: p.y - selection.minY)
    }

    private func complete(_ action: CaptureAction?) {
        textInput?.commit()
        let pixelRect = CGRect(
            x: selection.minX * scale,
            y: (bounds.height - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
        guard let cropped = image.cropping(to: pixelRect) else { onFinish?(nil); return }
        onFinish?(Outcome(image: cropped, rect: selection, annotations: annotations, action: action))
    }
}
