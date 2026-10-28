import AppKit
import PolyMacL10n

/// 화면 아래쪽에 잠깐 떴다 사라지는 안내. 클릭을 가로채지 않는다.
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    public static func show(_ message: String, duration: TimeInterval = 2) {
        let style = ToastStyle.current
        guard style.isEnabled else { return }
        show(message, duration: style.duration(for: duration), style: style)
    }

    /// style: 환경 설정 미리보기처럼 저장 전 모양으로 띄울 때. 알림을 꺼 두었어도 띄우고, duration은 그대로 쓴다.
    public static func show(_ message: String, duration: TimeInterval, style: ToastStyle) {
        let style = style.clamped
        let pad = CGFloat(style.padding)
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: CGFloat(style.fontSize), weight: .medium)
        // 정하지 않았으면 시스템 라이트·다크 모드를 따르는 글자색 — 흰 글자가 밝은 배경에 묻히지 않게
        label.textColor = style.textColor.flatMap(ToastStyle.color(hex:)) ?? .labelColor
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = CGFloat(style.maxWidth)
        let textSize = label.fittingSize
        let size = NSSize(width: textSize.width + pad * 2 + 4, height: textSize.height + pad * 2)

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
        label.frame = NSRect(x: pad + 2, y: pad, width: textSize.width, height: textSize.height)
        background.addSubview(label)
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
