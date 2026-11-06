import CoreGraphics

/// 클립보드 패널을 화면의 어디에 놓을지. 창과 무관한 계산만 둔다.
enum PanelPlacement {
    /// 화면 가장자리에서 띄우는 간격
    static let margin: CGFloat = 8
    /// 커서가 패널 위쪽 가장자리에서 이만큼 아래에 오게 놓는다
    static let cursorFromTop: CGFloat = 40

    /// 커서 근처에 놓되, 공간이 모자라면 화면 안으로 밀어 넣는다. 가로는 목록 가운데를 커서에 맞춘다.
    static func frame(size: CGSize, cursor: CGPoint, listWidth: CGFloat, visible: CGRect) -> CGRect {
        let origin = CGPoint(x: cursor.x - listWidth / 2, y: cursor.y - size.height + cursorFromTop)
        return inside(CGRect(origin: origin, size: size), visible: visible)
    }

    /// 화면 안으로 밀어 넣는다. 패널이 화면보다 크면 검색창과 목록이 있는 왼쪽 위를 살린다.
    static func inside(_ frame: CGRect, visible: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(min(frame.origin.x, visible.maxX - frame.width - margin), visible.minX + margin)
        frame.origin.y = min(max(frame.origin.y, visible.minY + margin), visible.maxY - frame.height - margin)
        return frame
    }
}
