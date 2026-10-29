import AppKit
import PolyMacL10n

/// 캡처 위에 그리는 표시 도구.
public enum AnnotationTool: String, CaseIterable, Sendable {
    case rectangle, arrow, pen, text, mosaic, number

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "scribble"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        case .number: return "1.circle"
        }
    }

    var title: String {
        switch self {
        case .rectangle: return L("사각형 (R)", "Rectangle (R)")
        case .arrow: return L("화살표 (A)", "Arrow (A)")
        case .pen: return L("펜 (P)", "Pen (P)")
        case .text: return L("글자 (E) — 클릭한 곳에 입력, ↩ 확정", "Text (E) — click to type, ↩ to finish")
        case .mosaic: return L("모자이크 (M) — 가릴 곳을 드래그", "Mosaic (M) — drag over what to hide")
        case .number: return L("번호 (N) — 클릭할 때마다 1, 2, 3…", "Number (N) — each click adds 1, 2, 3…")
        }
    }

    /// 드래그하지 않고 클릭 한 번으로 놓는 도구
    public var placesOnClick: Bool { self == .text || self == .number }
}

/// 표시 하나. 좌표는 캡처 영역 왼쪽 아래 기준 포인트 — 이미지에 굽지 않고 따로 들고 있어 나중에 다시 고칠 수 있다.
public struct Annotation {
    public var tool: AnnotationTool
    /// 사각형·화살표: [시작, 끝], 펜: 지나간 점들
    public var points: [CGPoint]
    public var color: NSColor
    public var lineWidth: CGFloat
    /// 글자 도구의 내용 (points[0]이 첫 줄의 왼쪽 위)
    public var text: String?
    /// 번호 도구의 숫자 (points[0]이 동그라미 가운데)
    public var number: Int?

    public init(tool: AnnotationTool, start: CGPoint, color: NSColor, lineWidth: CGFloat = 3) {
        self.tool = tool
        self.points = [start, start]
        self.color = color
        self.lineWidth = lineWidth
    }

    /// 다음 번호 — 이미 놓인 번호 중 가장 큰 것 + 1
    public static func nextNumber(after annotations: [Annotation]) -> Int {
        (annotations.compactMap(\.number).max() ?? 0) + 1
    }

    public mutating func extend(to point: CGPoint) {
        switch tool {
        case .pen: points.append(point)
        case .text, .number: points = [point, point] // 누른 채 끌면 놓을 자리를 옮긴다
        default: points[1] = point
        }
    }

    /// 클릭만 하고 끌지 않은 표시는 버린다 (글자·번호는 클릭으로 놓는다)
    public var isMeaningful: Bool {
        guard let first = points.first, let last = points.last else { return false }
        switch tool {
        case .pen: return points.count > 2
        case .text: return !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number: return number != nil
        default: return hypot(last.x - first.x, last.y - first.y) > 3
        }
    }

    /// 사각형·모자이크의 영역
    var rect: CGRect {
        let a = points[0], b = points[points.count - 1]
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

private extension NSColor {
    /// 밝기 0~1 (시스템 색처럼 HSB로 바로 못 읽는 색도)
    var brightness: CGFloat { usingColorSpace(.sRGB)?.brightnessComponent ?? 0 }
}

public enum AnnotationRenderer {
    /// 글자 크기 (포인트)
    public static let fontSize: CGFloat = 20

    /// 모자이크가 가릴 원본 그림: 표시 좌표 (0,0)이 그림의 어디(포인트, 왼쪽 아래 기준)에 해당하는지
    public struct Source {
        public let image: CGImage
        public let scale: CGFloat
        public let origin: CGPoint
        public init(image: CGImage, scale: CGFloat, origin: CGPoint = .zero) {
            self.image = image
            self.scale = scale
            self.origin = origin
        }
    }

    public static func draw(_ annotations: [Annotation], in ctx: CGContext, source: Source? = nil) {
        for a in annotations where a.points.count >= 2 {
            ctx.saveGState()
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setFillColor(a.color.cgColor)
            ctx.setLineWidth(a.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let start = a.points[0], end = a.points[a.points.count - 1]
            switch a.tool {
            case .rectangle:
                ctx.stroke(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
            case .arrow:
                let angle = atan2(end.y - start.y, end.x - start.x)
                let head = max(14, a.lineWidth * 4.5)
                let spread: CGFloat = .pi / 7
                // 선이 화살촉 끝을 뚫고 나오지 않게 조금 짧게
                ctx.move(to: start)
                ctx.addLine(to: CGPoint(x: end.x - cos(angle) * head * 0.7, y: end.y - sin(angle) * head * 0.7))
                ctx.strokePath()
                ctx.move(to: end)
                ctx.addLine(to: CGPoint(x: end.x - cos(angle - spread) * head, y: end.y - sin(angle - spread) * head))
                ctx.addLine(to: CGPoint(x: end.x - cos(angle + spread) * head, y: end.y - sin(angle + spread) * head))
                ctx.closePath()
                ctx.fillPath()
            case .pen:
                ctx.addLines(between: a.points)
                ctx.strokePath()
            case .mosaic:
                drawMosaic(a.rect, source: source, in: ctx)
            case .text:
                drawText(a.text ?? "", at: start, color: a.color, in: ctx)
            case .number:
                drawNumber(a.number ?? 0, at: start, color: a.color, in: ctx)
            }
            ctx.restoreGState()
        }
    }

    /// 원본을 큰 칸으로 줄였다 늘려 알아볼 수 없게. 원본이 없으면 회색으로 덮는다.
    private static func drawMosaic(_ rect: CGRect, source: Source?, in ctx: CGContext) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        guard let source else {
            ctx.setFillColor(NSColor.gray.cgColor)
            ctx.fill(rect)
            return
        }
        let s = source.scale
        let pixel = CGRect(x: (rect.minX + source.origin.x) * s,
                           y: CGFloat(source.image.height) - (rect.maxY + source.origin.y) * s,
                           width: rect.width * s, height: rect.height * s).integral
        guard let piece = source.image.cropping(to: pixel) else { return }
        let block: CGFloat = 10 // 칸 하나의 크기 (포인트)
        let w = max(1, Int(rect.width / block)), h = max(1, Int(rect.height / block))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        small.interpolationQuality = .medium
        small.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let tiles = small.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.draw(tiles, in: rect)
        ctx.restoreGState()
    }

    /// 여러 줄 글자. 바탕과 상관없이 보이게 반대색 테두리를 두른다.
    private static func drawText(_ text: String, at topLeft: CGPoint, color: NSColor, in ctx: CGContext) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let outline = color.brightness > 0.6 ? NSColor.black : NSColor.white
        var y = topLeft.y
        for line in text.components(separatedBy: "\n") {
            y -= font.ascender
            let attributed = NSAttributedString(string: line, attributes: [
                .font: font, .foregroundColor: color, .strokeColor: outline, .strokeWidth: -3,
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: topLeft.x, y: y)
            CTLineDraw(ctLine, ctx)
            y -= -font.descender + font.leading + 2
        }
    }

    /// 색 동그라미 안의 흰 숫자
    private static func drawNumber(_ number: Int, at center: CGPoint, color: NSColor, in ctx: CGContext) {
        let radius: CGFloat = 13
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let textColor = color.brightness > 0.75 ? NSColor.black : NSColor.white
        let attributed = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: textColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        // 글자 영역은 현재 글자 위치 기준으로 재므로, 앞 표시가 옮겨 둔 위치를 먼저 원점으로 돌린다
        ctx.textPosition = .zero
        let bounds = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    /// 픽셀 이미지 위에 표시를 합성한 새 이미지. 표시가 없으면 원본 그대로.
    public static func composite(_ image: CGImage, scale: CGFloat, annotations: [Annotation]) -> CGImage {
        guard !annotations.isEmpty,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.scaleBy(x: scale, y: scale)
        draw(annotations, in: ctx, source: Source(image: image, scale: scale))
        return ctx.makeImage() ?? image
    }
}

/// 캡처 편집·핀 편집에서 같이 쓰는 도구 막대.
@MainActor
public final class AnnotationToolbar: NSView {
    public enum Action: Equatable {
        case tool(AnnotationTool?)
        case undo
        case ocr, pin, save, copy, cancel
        case done
    }

    /// 1~8 키로도 고른다. 첫 번째(빨강)가 기본값.
    public static var palette: [(name: String, color: NSColor)] { [
        (L("빨강", "Red"), .systemRed), (L("주황", "Orange"), .systemOrange), (L("노랑", "Yellow"), .systemYellow), (L("초록", "Green"), .systemGreen),
        (L("파랑", "Blue"), .systemBlue), (L("보라", "Purple"), .systemPurple), (L("검정", "Black"), .black), (L("흰색", "White"), .white),
    ] }

    public var onAction: ((Action) -> Void)?
    public private(set) var selectedTool: AnnotationTool?
    public private(set) var color: NSColor = AnnotationToolbar.palette[0].color

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var swatches: [SwatchButton] = []

    /// output: 캡처 직후(텍스트 추출·핀·저장·복사·취소) / false면 핀 편집용(완료만)
    public init(output: Bool) {
        super.init(frame: .zero)
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for tool in AnnotationTool.allCases {
            let b = button(tool.symbol, tool.title, #selector(toolTapped(_:)))
            b.setButtonType(.pushOnPushOff)
            b.tag = AnnotationTool.allCases.firstIndex(of: tool)!
            toolButtons[tool] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(separator())
        for (i, entry) in Self.palette.enumerated() {
            let swatch = SwatchButton(color: entry.color)
            swatch.target = self
            swatch.action = #selector(swatchTapped(_:))
            swatch.tag = i
            swatch.toolTip = "\(entry.name) (\(i + 1))"
            swatch.isChosen = i == 0
            swatches.append(swatch)
            stack.addArrangedSubview(swatch)
        }
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(button("arrow.uturn.backward", L("되돌리기 (⌘Z)", "Undo (⌘Z)"), #selector(undoTapped)))
        stack.addArrangedSubview(separator())

        if output {
            stack.addArrangedSubview(button("text.viewfinder", L("텍스트 추출 (T)", "Extract text (T)"), #selector(ocrTapped)))
            stack.addArrangedSubview(button("pin", L("화면에 고정 (F)", "Pin to screen (F)"), #selector(pinTapped)))
            stack.addArrangedSubview(button("square.and.arrow.down", L("저장… (⌘S)", "Save… (⌘S)"), #selector(saveTapped)))
            stack.addArrangedSubview(separator())
            stack.addArrangedSubview(button("xmark", L("취소 (Esc)", "Cancel (Esc)"), #selector(cancelTapped)))
            let copy = button("checkmark", L("복사하고 닫기 (↩︎ 또는 ⌘C)", "Copy and close (↩︎ or ⌘C)"), #selector(copyTapped))
            copy.contentTintColor = .systemGreen
            stack.addArrangedSubview(copy)
        } else {
            let done = button("checkmark", L("편집 완료", "Done editing"), #selector(doneTapped))
            done.contentTintColor = .systemGreen
            stack.addArrangedSubview(done)
        }

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setFrameSize(fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func select(_ tool: AnnotationTool?) {
        selectedTool = tool
        for (t, b) in toolButtons { b.state = t == tool ? .on : .off }
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config) ?? NSImage()
        let b = FirstClickButton(image: image, target: self, action: action)
        b.bezelStyle = .accessoryBarAction
        b.isBordered = true
        b.toolTip = tip
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return b
    }

    private func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }

    @objc private func toolTapped(_ sender: NSButton) {
        let tool = AnnotationTool.allCases[sender.tag]
        select(selectedTool == tool ? nil : tool)
        onAction?(.tool(selectedTool))
    }

    /// 0부터. 키보드 1~8에서도 부른다.
    public func selectColor(_ index: Int) {
        guard Self.palette.indices.contains(index) else { return }
        color = Self.palette[index].color
        for (i, s) in swatches.enumerated() { s.isChosen = i == index }
        // 색을 고르면 바로 그릴 수 있게, 도구가 없으면 사각형
        if selectedTool == nil {
            select(.rectangle)
            onAction?(.tool(.rectangle))
        }
    }

    @objc private func swatchTapped(_ sender: NSButton) {
        selectColor(sender.tag)
    }

    @objc private func undoTapped() { onAction?(.undo) }
    @objc private func ocrTapped() { onAction?(.ocr) }
    @objc private func pinTapped() { onAction?(.pin) }
    @objc private func saveTapped() { onAction?(.save) }
    @objc private func copyTapped() { onAction?(.copy) }
    @objc private func cancelTapped() { onAction?(.cancel) }
    @objc private func doneTapped() { onAction?(.done) }
}

/// 도구 막대는 앞으로 오지 않는 패널에 있어 첫 클릭이 "창 앞으로"에 쓰이지 않게
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 색상 동그라미 버튼 (고른 색은 흰 테두리)
private final class SwatchButton: NSButton {
    private let swatch: NSColor
    var isChosen = false { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(color: NSColor) {
        swatch = color
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        title = ""
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = isChosen ? 18 : 14
        let dot = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        if isChosen {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2))
            ring.lineWidth = 2
            ring.stroke()
        }
        swatch.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSColor.black.withAlphaComponent(0.3).setStroke()
        NSBezierPath(ovalIn: dot).stroke()
    }
}


/// 글자 도구의 입력 칸 — 클릭한 자리에 띄우고 ↩로 확정, Esc로 취소, 다른 곳을 누르면 확정
@MainActor
public final class AnnotationTextInput: NSObject, NSTextFieldDelegate {
    private let field: NSTextField
    private var onCommit: ((String) -> Void)?
    private var finished = false

    /// point: view 좌표의 첫 줄 왼쪽 위, zoom: 화면에 보이는 배율(핀 확대 등)
    public init(in view: NSView, at point: NSPoint, color: NSColor, zoom: CGFloat = 1, onCommit: @escaping (String) -> Void) {
        let font = NSFont.systemFont(ofSize: AnnotationRenderer.fontSize * zoom, weight: .semibold)
        let height = ceil(font.ascender - font.descender + font.leading) + 4
        field = NSTextField(frame: NSRect(x: point.x - 2, y: point.y - height + 2, width: 240, height: height))
        self.onCommit = onCommit
        super.init()
        field.font = font
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = L("글자 입력 후 ↩", "Type, then ↩")
        field.delegate = self
        view.addSubview(field)
        view.window?.makeFirstResponder(field)
    }

    public var isActive: Bool { !finished }

    /// 입력 중인 내용을 확정하고 칸을 닫는다
    public func commit() {
        guard !finished else { return }
        finished = true
        let text = field.stringValue
        field.removeFromSuperview()
        let callback = onCommit
        onCommit = nil
        callback?(text)
    }

    public func cancel() {
        guard !finished else { return }
        field.stringValue = ""
        commit()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commit(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancel(); return true
        default: return false
        }
    }

    // 글자 수에 맞춰 칸을 넓힌다
    public func controlTextDidChange(_ obj: Notification) {
        let width = max(240, field.attributedStringValue.size().width + 24)
        field.setFrameSize(NSSize(width: width, height: field.frame.height))
    }
}
