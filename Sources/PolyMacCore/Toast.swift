import AppKit
import PolyMacL10n

/// 화면 아래쪽에 잠깐 떴다 사라지는 안내. 클릭을 가로채지 않는다.
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// message: 안내 문구. 첫 줄은 제목(가운데·굵게), 다음 줄부터는 보조 설명(가운데).
    /// content: 추출한 글처럼 안내와 섞이면 안 되는 내용 — 아래 별도 상자에 왼쪽 정렬로.
    public static func show(_ message: String, content: String? = nil, duration: TimeInterval = 2) {
        let style = ToastStyle.current
        guard style.isEnabled else { return }
        show(message, content: content, duration: style.duration(for: duration), style: style)
    }

    /// style: 환경 설정 미리보기처럼 저장 전 모양으로 띄울 때. 알림을 꺼 두었어도 띄우고, duration은 그대로 쓴다.
    public static func show(_ message: String, content: String? = nil, duration: TimeInterval, style: ToastStyle) {
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

        // 위에서부터 제목 → 보조 설명 → 내용 상자. 폭은 가장 넓은 줄에 맞춘다.
        let titleSize = title.fittingSize
        let subtitleSize = subtitle?.fittingSize ?? .zero
        let bodySize = body?.fittingSize ?? .zero
        let width = min(max(titleSize.width, subtitleSize.width, body == nil ? 0 : bodySize.width + contentInset * 2, 120), maxWidth)
        let gap: CGFloat = 4, sectionGap: CGFloat = 8
        let boxHeight = body == nil ? 0 : bodySize.height + contentInset * 2
        var height = titleSize.height
        if subtitle != nil { height += gap + subtitleSize.height }
        if body != nil { height += sectionGap + boxHeight }
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

        let panel = panel ?? makePanel()
        self.panel = panel

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
                    MainActor.assumeIsolated { panel.orderOut(nil) }
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
