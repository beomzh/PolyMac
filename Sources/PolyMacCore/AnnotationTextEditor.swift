import AppKit
import PolyMacL10n

extension Annotation {
    /// 글자 크기를 끌어 바꿀 수 있는 범위 (포인트)
    static let textSizes: ClosedRange<CGFloat> = 10...160

    /// 누른 점을 첫 줄의 세로 가운데로 — I자 커서가 가리키는 자리에 글자가 놓인다. 돌려주는 값은 첫 줄의 왼쪽 위.
    public static func textOrigin(click: CGPoint, fontSize: CGFloat) -> CGPoint {
        CGPoint(x: click.x, y: click.y + AnnotationRenderer.lineHeight(fontSize) / 2)
    }

    public mutating func offset(dx: CGFloat, dy: CGFloat) {
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// 글자의 corner 모서리를 point로 끌었을 때. 맞은편 모서리는 그대로 두고 글자 크기를 바꾼다.
    func textResized(from corner: AnnotationTextEditor.Corner, to point: CGPoint) -> Annotation {
        let box = AnnotationRenderer.textBounds(self)
        let anchor = CGPoint(x: corner.isLeft ? box.maxX : box.minX, y: corner.isTop ? box.minY : box.maxY)
        let factor = max(abs(point.x - anchor.x) / max(box.width, 1), abs(point.y - anchor.y) / max(box.height, 1))
        let size = min(max((fontSize * factor).rounded(), Self.textSizes.lowerBound), Self.textSizes.upperBound)
        var result = self
        result.fontSize = size
        let scaled = AnnotationRenderer.textBounds(result)
        let top = CGPoint(x: corner.isLeft ? anchor.x - scaled.width : anchor.x,
                          y: corner.isTop ? anchor.y + scaled.height : anchor.y)
        result.points = [top, top]
        return result
    }
}

/// 캡처·핀에서 같이 쓰는 글자 표시 편집: 놓을 자리 미리 보기, 고르기, 옮기기, 크기 바꾸기, 고쳐 쓰기, 지우기, 되돌리기.
/// 좌표는 표시 좌표(annotation). 화면 좌표로 바꾸는 일과 표시 목록은 쓰는 쪽이 넘겨준다.
@MainActor
public final class AnnotationTextEditor {
    public enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
    }

    public enum Press {
        case none, grabbed, edit
    }

    private enum Grab {
        case move(Annotation, from: CGPoint)
        case resize(Annotation, Corner)
    }

    private weak var view: NSView?
    private let get: () -> [Annotation]
    private let set: ([Annotation]) -> Void
    private let toView: (CGPoint) -> NSPoint
    private let zoom: () -> CGFloat

    public private(set) var selected: Int?
    private var grab: Grab?
    private var moved = false
    private var history: [[Annotation]] = []
    private var input: AnnotationTextInput?
    private var hover: (point: CGPoint, color: NSColor)?

    /// toView: 표시 좌표 → view 좌표, zoom: 화면에 보이는 배율
    public init(view: NSView, get: @escaping () -> [Annotation], set: @escaping ([Annotation]) -> Void,
                toView: @escaping (CGPoint) -> NSPoint, zoom: @escaping () -> CGFloat = { 1 }) {
        self.view = view
        self.get = get
        self.set = set
        self.toView = toView
        self.zoom = zoom
    }

    private var handleSize: CGFloat { 8 / zoom() }

    public var isTyping: Bool { input?.isActive == true }

    /// 입력 중이던 글자를 확정한다. 입력 중이었으면 true.
    @discardableResult
    public func commitInput() -> Bool {
        guard let input, input.isActive else { return false }
        input.commit()
        return true
    }

    public func reset() {
        selected = nil
        grab = nil
        hover = nil
        history.removeAll()
    }

    public func select(_ index: Int?) {
        selected = index
        view?.needsDisplay = true
    }

    /// 표시 목록을 바꾸기 직전에 부른다 (⌘Z로 돌아갈 자리)
    public func willChange() {
        history.append(get())
    }

    /// 되돌렸으면 true. 이 편집기가 모르는 이전 표시뿐이면 false.
    public func undo() -> Bool {
        guard let last = history.popLast() else { return false }
        set(last)
        selected = nil
        view?.needsDisplay = true
        return true
    }

    /// 표시 좌표계 자체가 옮겨졌을 때 (영역 이동)
    public func shift(dx: CGFloat, dy: CGFloat) {
        history = history.map { $0.map { var a = $0; a.offset(dx: dx, dy: dy); return a } }
    }

    // MARK: - 찾기

    /// 맨 위에 있는 글자부터
    static func hitText(_ annotations: [Annotation], at point: CGPoint) -> Int? {
        annotations.indices.last { annotations[$0].tool == .text && AnnotationRenderer.textBounds(annotations[$0]).insetBy(dx: -4, dy: -4).contains(point) }
    }

    static func corner(of box: CGRect, at point: CGPoint, tolerance: CGFloat) -> Corner? {
        Corner.allCases.first { corner in
            let x = corner.isLeft ? box.minX : box.maxX, y = corner.isTop ? box.maxY : box.minY
            return abs(point.x - x) <= tolerance && abs(point.y - y) <= tolerance
        }
    }

    private var selectedBox: CGRect? {
        let annotations = get()
        guard let selected, annotations.indices.contains(selected) else { return nil }
        return AnnotationRenderer.textBounds(annotations[selected])
    }

    public func cursor(at point: CGPoint) -> NSCursor? {
        if case .some = grab { return .closedHand }
        if let box = selectedBox, let corner = Self.corner(of: box, at: point, tolerance: handleSize) {
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch corner {
                case .topLeft: position = .topLeft
                case .topRight: position = .topRight
                case .bottomLeft: position = .bottomLeft
                case .bottomRight: position = .bottomRight
                }
                return .frameResize(position: position, directions: .all)
            }
            return .crosshair
        }
        return Self.hitText(get(), at: point) == nil ? nil : .openHand
    }

    /// 글자 도구로 눌렀을 때 글자가 놓일 자리를 흐리게 보여 준다. nil이면 지운다.
    public func updateHover(at point: CGPoint?, color: NSColor) {
        let next = point.flatMap { Self.hitText(get(), at: $0) == nil ? (point: $0, color: color) : nil }
        guard next != nil || hover != nil else { return }
        hover = next
        view?.needsDisplay = true
    }

    // MARK: - 마우스 · 키

    public func press(at point: CGPoint, clickCount: Int) -> Press {
        hover = nil
        if let box = selectedBox, let selected, let corner = Self.corner(of: box, at: point, tolerance: handleSize) {
            begin(.resize(get()[selected], corner))
            return .grabbed
        }
        guard let hit = Self.hitText(get(), at: point) else {
            select(nil)
            return .none
        }
        select(hit)
        if clickCount >= 2 { return .edit }
        begin(.move(get()[hit], from: point))
        return .grabbed
    }

    private func begin(_ next: Grab) {
        willChange()
        grab = next
        moved = false
        NSCursor.closedHand.set()
    }

    public func dragged(to point: CGPoint) {
        guard let selected, let grab else { return }
        var annotations = get()
        guard annotations.indices.contains(selected) else { return }
        switch grab {
        case .move(var start, let from):
            start.offset(dx: point.x - from.x, dy: point.y - from.y)
            annotations[selected] = start
        case .resize(let start, let corner):
            annotations[selected] = start.textResized(from: corner, to: point)
        }
        moved = true
        set(annotations)
        view?.needsDisplay = true
    }

    public func released() {
        guard grab != nil else { return }
        grab = nil
        if !moved { history.removeLast() }
    }

    /// 고른 글자가 있으면 지우고 true
    public func deleteSelected() -> Bool {
        var annotations = get()
        guard let selected, annotations.indices.contains(selected) else { return false }
        willChange()
        annotations.remove(at: selected)
        set(annotations)
        select(nil)
        return true
    }

    /// 고른 글자가 있으면 옮기고 true
    public func nudge(dx: CGFloat, dy: CGFloat) -> Bool {
        var annotations = get()
        guard let selected, annotations.indices.contains(selected) else { return false }
        willChange()
        annotations[selected].offset(dx: dx, dy: dy)
        set(annotations)
        view?.needsDisplay = true
        return true
    }

    // MARK: - 입력

    /// click 자리에 새 글자. 확정하면 골라 둔 상태가 되어 바로 옮기거나 크기를 바꿀 수 있다.
    public func beginText(at click: CGPoint, color: NSColor) {
        let top = Annotation.textOrigin(click: click, fontSize: AnnotationRenderer.fontSize)
        openInput(at: top, text: "", color: color, fontSize: AnnotationRenderer.fontSize) { [weak self] text in
            guard let self else { return }
            var a = Annotation(tool: .text, start: top, color: color)
            a.text = text
            guard a.isMeaningful else { return }
            self.willChange()
            self.set(self.get() + [a])
            self.selected = self.get().count - 1
        }
    }

    /// 고른 글자를 입력 칸으로 되돌린다. 비우고 확정하면 지워지고, Esc면 그대로.
    public func editSelected() {
        var annotations = get()
        guard let index = selected, annotations.indices.contains(index) else { return }
        let original = annotations[index]
        let before = annotations
        annotations.remove(at: index)
        set(annotations)
        selected = nil
        openInput(at: original.points[0], text: original.text ?? "", color: original.color, fontSize: original.fontSize) { [weak self] text in
            guard let self else { return }
            guard text != original.text else {
                self.set(before)
                self.selected = index
                return
            }
            self.history.append(before)
            var edited = original
            edited.text = text
            guard edited.isMeaningful else { return }
            var current = self.get()
            current.insert(edited, at: min(index, current.count))
            self.set(current)
            self.selected = index
        }
    }

    private func openInput(at top: CGPoint, text: String, color: NSColor, fontSize: CGFloat, onCommit: @escaping (String) -> Void) {
        guard let view else { return }
        input = AnnotationTextInput(in: view, at: toView(top), text: text, color: color, fontSize: fontSize, zoom: zoom()) { [weak self] result in
            guard let self else { return }
            onCommit(result)
            self.input = nil
            self.view?.window?.makeFirstResponder(self.view)
            self.view?.needsDisplay = true
        }
    }

    // MARK: - 그리기

    /// 표시 좌표 그대로인 ctx에 고른 글자의 테두리와 모서리, 놓일 자리 미리 보기를 그린다
    public func draw(in ctx: CGContext) {
        if let hover {
            var ghost = Annotation(tool: .text, start: Annotation.textOrigin(click: hover.point, fontSize: AnnotationRenderer.fontSize), color: hover.color.withAlphaComponent(0.55))
            ghost.text = L("글자", "Text")
            AnnotationRenderer.draw([ghost], in: ctx)
        }
        guard let box = selectedBox else { return }
        let width = 1 / zoom(), size = handleSize
        ctx.saveGState()
        ctx.setLineWidth(width)
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4 * width, 3 * width])
        ctx.stroke(box)
        ctx.setLineDash(phase: 0, lengths: [])
        for corner in Corner.allCases {
            let x = corner.isLeft ? box.minX : box.maxX, y = corner.isTop ? box.maxY : box.minY
            let handle = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(handle)
            ctx.stroke(handle)
        }
        ctx.restoreGState()
    }
}

/// 글자 도구의 입력 칸 — 놓일 자리에 마지막 모양 그대로 보여 준다. ↩ 확정, ⇧↩ 줄바꿈, Esc 취소, 다른 곳을 누르면 확정
@MainActor
final class AnnotationTextInput: NSObject, NSTextViewDelegate {
    private let textView: NSTextView
    private let hint: NSTextField
    private let initial: String
    private let zoom: CGFloat
    private var onCommit: ((String) -> Void)?
    private var finished = false
    private let top: NSPoint

    /// point: view 좌표의 첫 줄 왼쪽 위, zoom: 화면에 보이는 배율(핀 확대 등)
    init(in view: NSView, at point: NSPoint, text: String, color: NSColor, fontSize: CGFloat, zoom: CGFloat, onCommit: @escaping (String) -> Void) {
        initial = text
        self.zoom = zoom
        top = point
        self.onCommit = onCommit
        let size = fontSize * zoom
        textView = NSTextView(frame: NSRect(x: point.x, y: point.y - AnnotationRenderer.lineHeight(size), width: 40, height: AnnotationRenderer.lineHeight(size)))
        hint = NSTextField(labelWithString: L("↩ 확정 · ⇧↩ 줄바꿈 · Esc 취소", "↩ done · ⇧↩ new line · Esc cancel"))
        super.init()
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.insertionPointColor = color
        let attributes = AnnotationRenderer.textAttributes(size: size, color: color)
        textView.typingAttributes = attributes
        textView.string = text
        textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        textView.delegate = self
        textView.wantsLayer = true
        textView.layer?.borderWidth = 1
        textView.layer?.borderColor = NSColor.systemBlue.cgColor
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .white
        hint.drawsBackground = true
        hint.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        view.addSubview(textView)
        view.addSubview(hint)
        layout()
        view.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    var isActive: Bool { !finished }

    /// 입력 중인 내용을 확정하고 칸을 닫는다
    func commit() {
        guard !finished else { return }
        finished = true
        let text = textView.string
        textView.removeFromSuperview()
        hint.removeFromSuperview()
        let callback = onCommit
        onCommit = nil
        callback?(text)
    }

    private func cancel() {
        guard !finished else { return }
        textView.string = initial
        commit()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commit()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        layout()
    }

    /// 글자 수에 맞춰 칸을 키운다. 첫 줄 왼쪽 위는 그대로.
    private func layout() {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let line = textView.typingAttributes[.paragraphStyle].flatMap { ($0 as? NSParagraphStyle)?.minimumLineHeight } ?? 24
        let size = NSSize(width: max(ceil(used.width) + 4, 40), height: max(ceil(used.height), line))
        textView.frame = NSRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height)
        hint.sizeToFit()
        hint.setFrameOrigin(NSPoint(x: top.x, y: textView.frame.minY - hint.frame.height - 3))
    }
}
