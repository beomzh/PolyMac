import AppKit

/// 화면 아래쪽에 잠깐 떴다 사라지는 안내. 클릭을 가로채지 않는다.
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    public static func show(_ message: String, duration: TimeInterval = 2) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = 420
        let textSize = label.fittingSize
        let size = NSSize(width: textSize.width + 28, height: textSize.height + 20)

        let panel = panel ?? makePanel()
        self.panel = panel

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        label.frame = NSRect(x: 14, y: 10, width: textSize.width, height: textSize.height)
        background.addSubview(label)
        panel.contentView = background

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 80, width: size.width, height: size.height), display: true)
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
