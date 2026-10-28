import AppKit
import PolyMacL10n

/// 캡처 위에 그리는 표시 도구.
public enum AnnotationTool: String, CaseIterable, Sendable {
    case rectangle, arrow, pen

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "scribble"
        }
    }

    var title: String {
        switch self {
        case .rectangle: return L("사각형 (R)", "Rectangle (R)")
        case .arrow: return L("화살표 (A)", "Arrow (A)")
        case .pen: return L("펜 (P)", "Pen (P)")
        }
    }
}

/// 표시 하나. 좌표는 캡처 영역 왼쪽 아래 기준 포인트 — 이미지에 굽지 않고 따로 들고 있어 나중에 다시 고칠 수 있다.
public struct Annotation {
    public var tool: AnnotationTool
    /// 사각형·화살표: [시작, 끝], 펜: 지나간 점들
    public var points: [CGPoint]
    public var color: NSColor
    public var lineWidth: CGFloat

    public init(tool: AnnotationTool, start: CGPoint, color: NSColor, lineWidth: CGFloat = 3) {
        self.tool = tool
        self.points = [start, start]
        self.color = color
        self.lineWidth = lineWidth
    }

    public mutating func extend(to point: CGPoint) {
        if tool == .pen { points.append(point) } else { points[1] = point }
    }

    /// 클릭만 하고 끌지 않은 표시는 버린다
    public var isMeaningful: Bool {
        guard let first = points.first, let last = points.last else { return false }
        return tool == .pen ? points.count > 2 : hypot(last.x - first.x, last.y - first.y) > 3
    }
}

public enum AnnotationRenderer {
    public static func draw(_ annotations: [Annotation], in ctx: CGContext) {
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
            }
            ctx.restoreGState()
        }
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
        draw(annotations, in: ctx)
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
        let b = NSButton(image: image, target: self, action: action)
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

/// 색상 동그라미 버튼 (고른 색은 흰 테두리)
private final class SwatchButton: NSButton {
    private let swatch: NSColor
    var isChosen = false { didSet { needsDisplay = true } }

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
