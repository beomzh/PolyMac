import AppKit
import PolyMacL10n

/// 화면 아래쪽에 잠깐 떴다 사라지는 안내. 단추가 없으면 클릭을 가로채지 않는다.
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private static var actionTargets: [ActionTarget] = []

    /// 안내 아래 단추 (예: 인식한 글의 링크 열기). 누르면 안내를 닫는다.
    public struct Action {
        public let title: String
        public let handler: @MainActor () -> Void
        public init(_ title: String, handler: @escaping @MainActor () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    private final class ActionTarget: NSObject {
        let handler: @MainActor () -> Void
        init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
        @objc func run() {
            MainActor.assumeIsolated {
                handler()
                Toast.hide()
            }
        }
    }

    /// message: 안내 문구. 첫 줄은 제목(가운데·굵게), 다음 줄부터는 보조 설명(가운데).
    /// content: 추출한 글처럼 안내와 섞이면 안 되는 내용 — 아래 별도 상자에 왼쪽 정렬로.
    /// actions: 단추가 있으면 누를 시간을 주려고 6초 이상 띄운다 (알림을 꺼 두었어도 단추가 있으면 띄운다)
    public static func show(_ message: String, content: String? = nil, duration: TimeInterval = 2, actions: [Action] = []) {
        let style = ToastStyle.current
        guard style.isEnabled || !actions.isEmpty else { return }
        let shown = style.duration(for: duration)
        show(message, content: content, duration: actions.isEmpty ? shown : max(shown, 6), style: style, actions: actions)
    }

    public static func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        actionTargets.removeAll()
    }

    /// style: 환경 설정 미리보기처럼 저장 전 모양으로 띄울 때. 알림을 꺼 두었어도 띄우고, duration은 그대로 쓴다.
    public static func show(_ message: String, content: String? = nil, duration: TimeInterval, style: ToastStyle, actions: [Action] = []) {
        let style = style.clamped
        let pad = CGFloat(style.padding)
        let fontSize = CGFloat(style.fontSize)
        let maxWidth = CGFloat(style.maxWidth)
        // 정하지 않았으면 시스템 라이트·다크 모드를 따르는 글자색 — 흰 글자가 밝은 배경에 묻히지 않게
        let custom = style.textColor.flatMap(ToastStyle.color(hex:))
        let primary = custom ?? .labelColor
        let secondary = custom?.withAlphaComponent(0.75) ?? .secondaryLabelColor

        func label(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment, lines: Int) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: text)
            l.font = font
            l.textColor = color
            l.alignment = alignment
            l.maximumNumberOfLines = lines
            l.lineBreakMode = .byTruncatingTail
            l.preferredMaxLayoutWidth = maxWidth
            return l
        }

        var lines = message.components(separatedBy: "\n")
        let title = label(lines.removeFirst(), font: .systemFont(ofSize: fontSize + 1, weight: .bold), color: primary, alignment: .center, lines: 2)
        let rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = rest.isEmpty ? nil : label(rest, font: .systemFont(ofSize: fontSize - 1), color: secondary, alignment: .center, lines: 3)
        let contentInset: CGFloat = 8
        let body = content.map { text -> NSTextField in
            let l = label(text, font: .systemFont(ofSize: fontSize - 1), color: primary, alignment: .left, lines: 6)
            l.preferredMaxLayoutWidth = maxWidth - contentInset * 2
            return l
        }

        actionTargets = actions.map { ActionTarget($0.handler) }
        let buttons = zip(actions, actionTargets).map { action, target -> NSButton in
            let b = NSButton(title: action.title, target: target, action: #selector(ActionTarget.run))
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: fontSize - 1)
            b.lineBreakMode = .byTruncatingMiddle
            b.sizeToFit()
            b.frame.size.width = min(b.frame.width, maxWidth)
            return b
        }

        // 위에서부터 제목 → 보조 설명 → 내용 상자 → 단추. 폭은 가장 넓은 줄에 맞춘다.
        let titleSize = title.fittingSize
        let subtitleSize = subtitle?.fittingSize ?? .zero
        let bodySize = body?.fittingSize ?? .zero
        let buttonGap: CGFloat = 4
        let buttonHeight = buttons.map(\.frame.height).max() ?? 0
        let buttonsHeight = buttons.isEmpty ? 0 : buttonHeight * CGFloat(buttons.count) + buttonGap * CGFloat(buttons.count - 1)
        let width = min(max(titleSize.width, subtitleSize.width, body == nil ? 0 : bodySize.width + contentInset * 2,
                            buttons.map(\.frame.width).max() ?? 0, 120), maxWidth)
        let gap: CGFloat = 4, sectionGap: CGFloat = 8
        let boxHeight = body == nil ? 0 : bodySize.height + contentInset * 2
        var height = titleSize.height
        if subtitle != nil { height += gap + subtitleSize.height }
        if body != nil { height += sectionGap + boxHeight }
        if !buttons.isEmpty { height += sectionGap + buttonsHeight }
        let size = NSSize(width: width + pad * 2, height: height + pad * 2)

        // AppKit은 아래가 원점 — 위에서부터 놓으려고 y를 줄여 간다
        var y = size.height - pad - titleSize.height
        title.frame = NSRect(x: pad, y: y, width: width, height: titleSize.height)
        var views: [NSView] = [title]
        if let subtitle {
            y -= gap + subtitleSize.height
            subtitle.frame = NSRect(x: pad, y: y, width: width, height: subtitleSize.height)
            views.append(subtitle)
        }
        if let body {
            y -= sectionGap + boxHeight
            let box = NSView(frame: NSRect(x: pad, y: y, width: width, height: boxHeight))
            box.wantsLayer = true
            box.layer?.cornerRadius = 6
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                box.layer?.backgroundColor = primary.withAlphaComponent(0.08).cgColor
            }
            body.frame = NSRect(x: contentInset, y: contentInset, width: width - contentInset * 2, height: bodySize.height)
            box.addSubview(body)
            views.append(box)
        }
        // 단추는 한 줄에 하나씩, 가운데
        if !buttons.isEmpty { y -= sectionGap }
        for button in buttons {
            y -= button.frame.height
            button.frame.origin = NSPoint(x: pad + (width - button.frame.width) / 2, y: y)
            views.append(button)
            y -= buttonGap
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.ignoresMouseEvents = buttons.isEmpty

        let background: NSView
        if let fill = style.backgroundColor.flatMap(ToastStyle.color(hex:)) {
            background = NSView(frame: NSRect(origin: .zero, size: size))
            background.wantsLayer = true
            background.layer?.backgroundColor = fill.cgColor
        } else {
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            // 메뉴·팝오버와 같은 재질: 라이트 모드는 밝은 박스, 다크 모드는 어두운 박스
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            background = effect
        }
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        // 동적 색은 현재 모드로 풀어서 넣어야 라이트·다크가 맞는다
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            background.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        views.forEach(background.addSubview)
        panel.contentView = background

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(origin: style.position.origin(for: size, in: visible), size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        // 사라지는 동안 새 안내가 떴으면(투명도 1로 돌아옴) 그 안내는 두고
                        guard panel.alphaValue == 0 else { return }
                        panel.orderOut(nil)
                        actionTargets.removeAll()
                    }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        return p
    }
}
