import AppKit

/// 핀 가장자리·모서리를 끌어 크기 바꾸기. 비율은 원본 그대로, 끄는 반대쪽(가장자리면 가운데)을 고정한다.
struct PinResize {
    struct Edges: Equatable {
        var left = false, right = false, top = false, bottom = false
        var isEmpty: Bool { !(left || right || top || bottom) }
    }

    static let minZoom: CGFloat = 0.2
    static let maxZoom: CGFloat = 5

    /// 잡을 수 있는 띠 두께 (작은 핀은 가운데로 옮길 자리가 남게 줄인다)
    static func band(for size: NSSize) -> CGFloat {
        min(8, size.width / 4, size.height / 4)
    }

    /// 핀 안의 점이 어느 가장자리 띠에 있는지 (Cocoa 좌표, 왼쪽 아래 원점)
    static func edges(at point: NSPoint, in size: NSSize) -> Edges {
        let b = band(for: size)
        return Edges(left: point.x < b, right: point.x > size.width - b, top: point.y > size.height - b, bottom: point.y < b)
    }

    /// 시작 틀에서 마우스가 (dx, dy) 움직였을 때의 새 틀과 배율. 화면 좌표.
    static func frame(from start: NSRect, base: NSSize, edges: Edges, dx: CGFloat, dy: CGFloat) -> (NSRect, CGFloat) {
        var factors: [CGFloat] = []
        if edges.left || edges.right {
            factors.append((start.width + (edges.right ? dx : -dx)) / base.width)
        }
        if edges.top || edges.bottom {
            factors.append((start.height + (edges.top ? dy : -dy)) / base.height)
        }
        // 모서리는 더 많이 움직인 쪽을 따른다
        let current = start.width / base.width
        let factor = min(max(factors.max { abs($0 - current) < abs($1 - current) } ?? current, minZoom), maxZoom)
        let size = NSSize(width: base.width * factor, height: base.height * factor)
        let x = edges.left ? start.maxX - size.width : edges.right ? start.minX : start.midX - size.width / 2
        let y = edges.bottom ? start.maxY - size.height : edges.top ? start.minY : start.midY - size.height / 2
        return (NSRect(origin: NSPoint(x: x, y: y), size: size), factor)
    }

    static func cursor(for edges: Edges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch (edges.left, edges.right, edges.top, edges.bottom) {
            case (true, _, true, _): position = .topLeft
            case (_, true, true, _): position = .topRight
            case (true, _, _, true): position = .bottomLeft
            case (_, true, _, true): position = .bottomRight
            case (true, _, _, _): position = .left
            case (_, true, _, _): position = .right
            case (_, _, true, _): position = .top
            default: position = .bottom
            }
            return .frameResize(position: position, directions: .all)
        }
        return edges.left || edges.right ? .resizeLeftRight : .resizeUpDown
    }
}
