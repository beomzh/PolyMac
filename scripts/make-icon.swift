// PolyMac 앱 아이콘 생성기 — 그림을 코드로 그려 모든 크기를 같은 원본에서 만든다.
//
//   swift scripts/make-icon.swift [저장소경로] [디자인=cube]     → App/AppIcon.icns, docs/assets/logo.png
//   swift scripts/make-icon.swift [저장소경로] --sheet            → build/icon-options.png (모든 디자인 비교)
//
// 디자인 공통 주제: "여러 도구가 Mac 위의 하나의 앱으로"
//   hexagon  — 여섯 색 면(도구)이 모여 하나의 다면체, 가운데 흰 핵
//   tools    — 2×2 타일에 창 분할·캡처·텍스트 추출·클립보드 기호
//   prism    — 흰 빛 하나가 프리즘을 지나 여러 색 광선(도구)으로
//   monogram — 여러 색 조각으로 만든 P
//   stack    — 기능 모듈이 겹겹이 쌓인 판
//   window   — Mac 창 하나(신호등 버튼) 안에 도구 네 칸: 여러 도구가 하나의 Mac 앱 안에
//   beam     — 빛 하나가 프리즘을 지나 네 광선이 되고, 광선 끝마다 도구 하나: 하나의 앱에서 여러 도구가
//   cube     — 다면체(Poly) 큐브의 면마다 도구 기호: 한 덩어리에 여러 도구
import AppKit

let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
let option = args.count > 2 ? args[2] : "cube" // 현재 채택: 8. 다면체 큐브
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [UInt32], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors.map { color($0) } as CFArray, locations: locations)!
}

/// 중심에서 각도(도, 위쪽이 90)로 반지름만큼
func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: center.x + cos(r) * radius, y: center.y + sin(r) * radius)
}

/// macOS 아이콘 본체 (824pt 둥근 사각형, 여백 100)
func drawBody(_ ctx: CGContext, top: UInt32, bottom: UInt32, glow: UInt32? = nil) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(path)
    ctx.setFillColor(color(bottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([top, bottom]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    if let glow {
        let g = CGGradient(colorsSpace: space, colors: [color(glow, 0.35), color(glow, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: [])
    }
    let shine = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 3, dy: 3), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint, shadow: Bool = false) {
    ctx.saveGState()
    if shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x000000, 0.4))
        ctx.addPath(path)
        ctx.setFillColor(color(0x000000))
        ctx.fillPath()
    }
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// 기호를 평행사변형 면(origin + s·u + t·v) 위에 붙인다 — 큐브 면처럼 기울어진 곳에
func symbolOnFace(_ ctx: CGContext, _ name: String, origin: CGPoint, u: CGVector, v: CGVector, coverage: CGFloat = 0.56) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 200, weight: .bold).applying(.init(paletteColors: [.white])))
    else { return }
    let aspect = image.size.width / image.size.height
    let w = aspect >= 1 ? coverage : coverage * aspect, h = aspect >= 1 ? coverage / aspect : coverage
    // 기울인 좌표계에 벡터 기호를 바로 그리면 깨지므로, 먼저 비트맵으로 굽고 그 이미지를 면에 붙인다
    let px = 512
    let bitmap = CGContext(data: nil, width: Int(CGFloat(px) * w), height: Int(CGFloat(px) * h), bitsPerComponent: 8, bytesPerRow: 0,
                           space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
    image.draw(in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
    NSGraphicsContext.restoreGraphicsState()
    guard let glyph = bitmap.makeImage() else { return }
    ctx.saveGState()
    ctx.concatenate(CGAffineTransform(a: u.dx, b: u.dy, c: v.dx, d: v.dy, tx: origin.x, ty: origin.y))
    ctx.interpolationQuality = .high
    ctx.draw(glyph, in: CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h))
    ctx.restoreGState()
}

func symbol(_ ctx: CGContext, _ name: String, in rect: CGRect, pointSize: CGFloat) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold).applying(.init(paletteColors: [.white]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    let size = image.size
    let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - 디자인들

func hexagon(_ ctx: CGContext) {
    drawBody(ctx, top: 0x2A2F45, bottom: 0x0B0D14, glow: 0x7C5CFF)
    let center = CGPoint(x: 512, y: 512), radius: CGFloat = 300
    let faces: [(UInt32, UInt32)] = [(0x3B82F6, 0x60A5FA), (0x8B5CF6, 0xA78BFA), (0xEC4899, 0xF472B6),
                                     (0xF97316, 0xFB923C), (0xEAB308, 0xFDE047), (0x14B8A6, 0x5EEAD4)]
    for (i, face) in faces.enumerated() {
        let a = 90 + CGFloat(i) * 60
        let path = CGMutablePath()
        path.move(to: center)
        path.addLine(to: point(center, radius, a))
        path.addLine(to: point(center, radius, a + 60))
        path.closeSubpath()
        fill(ctx, path, gradient([face.0, face.1]), from: point(center, radius, a + 30), to: center)
    }
    ctx.setStrokeColor(color(0x11131C))
    ctx.setLineWidth(16)
    for i in 0..<6 {
        ctx.move(to: center)
        ctx.addLine(to: point(center, radius + 4, 90 + CGFloat(i) * 60))
    }
    ctx.strokePath()
    let core = CGMutablePath()
    for i in 0..<6 {
        let p = point(center, 92, 90 + CGFloat(i) * 60)
        i == 0 ? core.move(to: p) : core.addLine(to: p)
    }
    core.closeSubpath()
    fill(ctx, core, gradient([0xFFFFFF, 0xDCE3F5]), from: CGPoint(x: 512, y: 604), to: CGPoint(x: 512, y: 420), shadow: true)
}

func tools(_ ctx: CGContext) {
    drawBody(ctx, top: 0x2B3048, bottom: 0x0E1018)
    let tile: CGFloat = 300, gap: CGFloat = 36
    let origin = CGPoint(x: 512 - tile - gap / 2, y: 512 - tile - gap / 2)
    let items: [(Int, Int, UInt32, UInt32, String)] = [
        (0, 1, 0x3B82F6, 0x2563EB, "rectangle.split.2x1.fill"), // 창 분할
        (1, 1, 0xA855F7, 0x7C3AED, "viewfinder"),               // 캡처
        (0, 0, 0xF97316, 0xEA580C, "text.viewfinder"),          // 텍스트 추출
        (1, 0, 0x14B8A6, 0x0D9488, "doc.on.clipboard.fill"),    // 클립보드
    ]
    for t in items {
        let rect = CGRect(x: origin.x + CGFloat(t.0) * (tile + gap), y: origin.y + CGFloat(t.1) * (tile + gap), width: tile, height: tile)
        let path = CGPath(roundedRect: rect, cornerWidth: 70, cornerHeight: 70, transform: nil)
        fill(ctx, path, gradient([t.2, t.3]), from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY), shadow: true)
        symbol(ctx, t.4, in: rect, pointSize: 120)
    }
}

func prism(_ ctx: CGContext) {
    drawBody(ctx, top: 0x23263A, bottom: 0x08090F)
    // 들어오는 흰 빛
    ctx.saveGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 150, y: 470))
    ctx.addLine(to: CGPoint(x: 430, y: 520))
    ctx.strokePath()
    ctx.restoreGState()
    // 나가는 여섯 광선 = 여섯 도구
    let rays: [UInt32] = [0xEF4444, 0xF97316, 0xEAB308, 0x22C55E, 0x3B82F6, 0xA855F7]
    for (i, c) in rays.enumerated() {
        let spread = CGFloat(i) - 2.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 560, y: 520 + spread * 6))
        path.addLine(to: CGPoint(x: 924, y: 600 - spread * 52 - 26))
        path.addLine(to: CGPoint(x: 924, y: 600 - spread * 52 + 26))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(color(c, 0.9))
        ctx.fillPath()
        ctx.restoreGState()
    }
    // 유리 삼각형
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: 512, y: 760))
    tri.addLine(to: CGPoint(x: 300, y: 330))
    tri.addLine(to: CGPoint(x: 724, y: 330))
    tri.closeSubpath()
    ctx.saveGState()
    ctx.addPath(tri)
    ctx.clip()
    let glass = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.55), color(0xC7D2FE, 0.25), color(0xFFFFFF, 0.08)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: 400, y: 760), end: CGPoint(x: 640, y: 330), options: [])
    ctx.restoreGState()
    ctx.addPath(tri)
    ctx.setStrokeColor(color(0xFFFFFF, 0.95))
    ctx.setLineWidth(12)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func monogram(_ ctx: CGContext) {
    drawBody(ctx, top: 0x262A3F, bottom: 0x0C0E16, glow: 0x3B82F6)
    // 세로 기둥: 세 조각
    let stemColors: [(UInt32, UInt32)] = [(0x60A5FA, 0x3B82F6), (0x3B82F6, 0x2563EB), (0x2563EB, 0x1D4ED8)]
    for (i, c) in stemColors.enumerated() {
        let rect = CGRect(x: 300, y: 690 - CGFloat(i) * 180, width: 150, height: 160)
        fill(ctx, CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil), gradient([c.0, c.1]),
             from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY), shadow: true)
    }
    // 둥근 고리: 네 조각
    let center = CGPoint(x: 520, y: 645), outer: CGFloat = 205, inner: CGFloat = 85
    let segments: [(CGFloat, CGFloat, UInt32, UInt32)] = [
        (90, 25, 0xA855F7, 0x8B5CF6), (25, -40, 0xEC4899, 0xDB2777), (-40, -95, 0xF97316, 0xEA580C), (-95, -125, 0xEAB308, 0xCA8A04),
    ]
    for s in segments {
        let path = CGMutablePath()
        path.addArc(center: center, radius: outer, startAngle: s.0 * .pi / 180 - 0.04, endAngle: s.1 * .pi / 180 + 0.04, clockwise: true)
        path.addArc(center: center, radius: inner, startAngle: s.1 * .pi / 180 + 0.04, endAngle: s.0 * .pi / 180 - 0.04, clockwise: false)
        path.closeSubpath()
        fill(ctx, path, gradient([s.2, s.3]), from: point(center, outer, (s.0 + s.1) / 2), to: center, shadow: true)
    }
    // 고리 왼쪽은 기둥과 붙어 있게
    let bridge = CGPath(roundedRect: CGRect(x: 420, y: 560, width: 100, height: 290), cornerWidth: 10, cornerHeight: 10, transform: nil)
    fill(ctx, bridge, gradient([0x8B5CF6, 0x6D28D9]), from: CGPoint(x: 470, y: 850), to: CGPoint(x: 470, y: 560))
    fill(ctx, CGPath(roundedRect: CGRect(x: 300, y: 690, width: 150, height: 160), cornerWidth: 36, cornerHeight: 36, transform: nil),
         gradient([0x60A5FA, 0x3B82F6]), from: CGPoint(x: 375, y: 850), to: CGPoint(x: 375, y: 690))
}

func stack(_ ctx: CGContext) {
    drawBody(ctx, top: 0x272B40, bottom: 0x0B0D15, glow: 0x14B8A6)
    // 아이소메트릭 판 네 장 (아래부터)
    let plates: [(UInt32, UInt32)] = [(0x14B8A6, 0x0F766E), (0xF97316, 0xC2410C), (0xA855F7, 0x7E22CE), (0x3B82F6, 0x1D4ED8)]
    for (i, c) in plates.enumerated() {
        let y = 330 + CGFloat(i) * 105
        let top = CGMutablePath()
        top.move(to: CGPoint(x: 512, y: y + 150))
        top.addLine(to: CGPoint(x: 772, y: y + 30))
        top.addLine(to: CGPoint(x: 512, y: y - 90))
        top.addLine(to: CGPoint(x: 252, y: y + 30))
        top.closeSubpath()
        // 두께
        let side = CGMutablePath()
        side.move(to: CGPoint(x: 252, y: y + 30))
        side.addLine(to: CGPoint(x: 512, y: y - 90))
        side.addLine(to: CGPoint(x: 772, y: y + 30))
        side.addLine(to: CGPoint(x: 772, y: y + 6))
        side.addLine(to: CGPoint(x: 512, y: y - 114))
        side.addLine(to: CGPoint(x: 252, y: y + 6))
        side.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.45))
        ctx.addPath(side)
        ctx.setFillColor(color(c.1))
        ctx.fillPath()
        ctx.restoreGState()
        fill(ctx, top, gradient([c.0, c.1]), from: CGPoint(x: 512, y: y + 150), to: CGPoint(x: 512, y: y - 90))
    }
    // 맨 위 판의 흰 P 표시 대신 흰 점 — 하나의 앱
    let dot = CGPath(ellipseIn: CGRect(x: 467, y: 650, width: 90, height: 52), transform: nil)
    fill(ctx, dot, gradient([0xFFFFFF, 0xE2E8F0]), from: CGPoint(x: 512, y: 702), to: CGPoint(x: 512, y: 650))
}

/// 공통 도구 네 가지 (색, 기호)
let toolSet: [(UInt32, UInt32, String)] = [
    (0x3B82F6, 0x2563EB, "rectangle.split.2x1.fill"), // 창 분할
    (0xA855F7, 0x7C3AED, "viewfinder"),               // 캡처
    (0xF97316, 0xEA580C, "text.viewfinder"),          // 텍스트 추출
    (0x14B8A6, 0x0D9488, "doc.on.clipboard.fill"),    // 클립보드
]

func window(_ ctx: CGContext) {
    drawBody(ctx, top: 0x2B3048, bottom: 0x0E1018)
    // Mac 창
    let frame = CGRect(x: 180, y: 210, width: 664, height: 600)
    let framePath = CGPath(roundedRect: frame, cornerWidth: 56, cornerHeight: 56, transform: nil)
    fill(ctx, framePath, gradient([0xF1F5F9, 0xCBD5E1]), from: CGPoint(x: 512, y: frame.maxY), to: CGPoint(x: 512, y: frame.minY), shadow: true)
    // 제목 막대 + 신호등
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() as EnumeratedSequence<[UInt32]> {
        ctx.setFillColor(color(c))
        ctx.fillEllipse(in: CGRect(x: frame.minX + 46 + CGFloat(i) * 58, y: frame.maxY - 78, width: 38, height: 38))
    }
    // 창 안의 도구 네 칸
    let tile: CGFloat = 206, gap: CGFloat = 28
    let gridOrigin = CGPoint(x: 512 - tile - gap / 2, y: frame.minY + 40)
    for (i, t) in toolSet.enumerated() {
        let col = i % 2, row = 1 - i / 2
        let rect = CGRect(x: gridOrigin.x + CGFloat(col) * (tile + gap), y: gridOrigin.y + CGFloat(row) * (tile + gap), width: tile, height: tile)
        fill(ctx, CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil), gradient([t.0, t.1]),
             from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY))
        symbol(ctx, t.2, in: rect, pointSize: 86)
    }
}

func beam(_ ctx: CGContext) {
    drawBody(ctx, top: 0x23263A, bottom: 0x08090F)
    let tile: CGFloat = 132, gap: CGFloat = 22
    let tileX: CGFloat = 690
    let firstY = 512 + (tile * 2 + gap * 1.5) - tile
    let exit = CGPoint(x: 470, y: 500)
    // 광선: 프리즘에서 각 도구 칸으로
    for (i, t) in toolSet.enumerated() {
        let ty = firstY - CGFloat(i) * (tile + gap) + tile / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: exit.x, y: exit.y + 6))
        path.addLine(to: CGPoint(x: tileX + 4, y: ty + 22))
        path.addLine(to: CGPoint(x: tileX + 4, y: ty - 22))
        path.addLine(to: CGPoint(x: exit.x, y: exit.y - 6))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(color(t.0, 0.85))
        ctx.fillPath()
        ctx.restoreGState()
    }
    for (i, t) in toolSet.enumerated() {
        let rect = CGRect(x: tileX, y: firstY - CGFloat(i) * (tile + gap), width: tile, height: tile)
        fill(ctx, CGPath(roundedRect: rect, cornerWidth: 32, cornerHeight: 32, transform: nil), gradient([t.0, t.1]),
             from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY), shadow: true)
        symbol(ctx, t.2, in: rect, pointSize: 62)
    }
    // 들어오는 흰 빛
    ctx.saveGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.95))
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 150, y: 430))
    ctx.addLine(to: CGPoint(x: 330, y: 482))
    ctx.strokePath()
    ctx.restoreGState()
    // 프리즘
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: 400, y: 700))
    tri.addLine(to: CGPoint(x: 240, y: 330))
    tri.addLine(to: CGPoint(x: 560, y: 330))
    tri.closeSubpath()
    ctx.saveGState()
    ctx.addPath(tri)
    ctx.clip()
    let glass = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.6), color(0xC7D2FE, 0.28), color(0xFFFFFF, 0.1)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: 320, y: 700), end: CGPoint(x: 500, y: 330), options: [])
    ctx.restoreGState()
    ctx.addPath(tri)
    ctx.setStrokeColor(color(0xFFFFFF, 0.95))
    ctx.setLineWidth(11)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func cube(_ ctx: CGContext) {
    drawBody(ctx, top: 0x2A2F45, bottom: 0x0B0D14, glow: 0x7C5CFF)
    let s: CGFloat = 285
    let c = CGPoint(x: 512, y: 455) // 앞쪽 모서리
    let u = CGVector(dx: cos(.pi / 6) * s, dy: sin(.pi / 6) * s)   // 오른쪽 위
    let v = CGVector(dx: -cos(.pi / 6) * s, dy: sin(.pi / 6) * s)  // 왼쪽 위
    let w = CGVector(dx: 0, dy: -s)                                // 아래
    func p(_ a: CGVector...) -> CGPoint { a.reduce(c) { CGPoint(x: $0.x + $1.dx, y: $0.y + $1.dy) } }
    func face(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        return path
    }
    // 그림자
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.55))
    ctx.addPath(face([p(w), p(w, u), p(u), p(u, v), p(v), p(v, w)]))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.restoreGState()
    // 윗면: 캡처, 왼쪽: 창 분할, 오른쪽: 클립보드
    let top = face([c, p(u), p(u, v), p(v)])
    let left = face([c, p(v), p(v, w), p(w)])
    let right = face([c, p(w), p(u, w), p(u)])
    fill(ctx, top, gradient([0xC084FC, 0xA855F7]), from: p(u, v), to: c)
    fill(ctx, left, gradient([0x3B82F6, 0x1D4ED8]), from: p(v), to: p(w))
    fill(ctx, right, gradient([0x14B8A6, 0x0F766E]), from: p(u), to: p(w))
    symbolOnFace(ctx, "viewfinder", origin: c, u: u, v: v)
    symbolOnFace(ctx, "rectangle.split.2x1.fill", origin: p(w), u: v, v: CGVector(dx: 0, dy: s))
    symbolOnFace(ctx, "doc.on.clipboard.fill", origin: p(w), u: u, v: CGVector(dx: 0, dy: s))
    // 모서리 하이라이트
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.setLineWidth(5)
    ctx.setLineJoin(.round)
    ctx.addPath(face([p(w), p(u, w), p(u), p(u, v), p(v), p(v, w)]))
    ctx.move(to: c); ctx.addLine(to: p(u))
    ctx.move(to: c); ctx.addLine(to: p(v))
    ctx.move(to: c); ctx.addLine(to: p(w))
    ctx.strokePath()
}

let designs: [(String, String, (CGContext) -> Void)] = [
    ("hexagon", "1. 육각 다면체 (현재)", hexagon),
    ("tools", "2. 도구 그리드", tools),
    ("prism", "3. 프리즘", prism),
    ("monogram", "4. 모노그램 P", monogram),
    ("stack", "5. 레이어 스택", stack),
    ("window", "6. Mac 창 속 도구들", window),
    ("beam", "7. 프리즘 → 도구", beam),
    ("cube", "8. 다면체 큐브", cube),
]

func render(_ draw: (CGContext) -> Void, pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try fm.createDirectory(at: root.appendingPathComponent("build"), withIntermediateDirectories: true)

if option == "--sheet" {
    // 비교용 한 장: 큰 그림 + 같은 아이콘을 Dock(64)·Finder(32)·메뉴(16) 크기로. 4번째 인수로 고를 수 있다 (tools,prism,...)
    let picked = args.count > 3 ? args[3].split(separator: ",").map(String.init) : designs.map(\.0)
    let designs = designs.filter { picked.contains($0.0) }
    let cell: CGFloat = 340, width = cell * CGFloat(designs.count), height: CGFloat = 470
    let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(color(0x1C1C1E))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    for (i, design) in designs.enumerated() {
        let x = CGFloat(i) * cell
        ctx.draw(render(design.2, pixels: 600), in: CGRect(x: x + 20, y: 130, width: 300, height: 300))
        var small = x + 90
        for size in [64, 32, 16] {
            let s = CGFloat(size)
            ctx.draw(render(design.2, pixels: size * 2), in: CGRect(x: small, y: 60 - s / 2 + 16, width: s, height: s))
            small += s + 24
        }
        (design.1 as NSString).draw(at: NSPoint(x: x + 24, y: 440),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white])
    }
    try png(ctx.makeImage()!).write(to: root.appendingPathComponent("build/icon-options.png"))
    print("✅ build/icon-options.png")
    exit(0)
}

guard let chosen = designs.first(where: { $0.0 == option }) else { fatalError("알 수 없는 디자인: \(option)") }
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(render(chosen.2, pixels: points)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(render(chosen.2, pixels: points * 2)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let assets = root.appendingPathComponent("docs/assets")
try fm.createDirectory(at: assets, withIntermediateDirectories: true)
try png(render(chosen.2, pixels: 512)).write(to: assets.appendingPathComponent("logo.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("App/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("✅ \(chosen.1) → App/AppIcon.icns, docs/assets/logo.png")
