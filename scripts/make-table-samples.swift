// 표 인식 측정용 합성 샘플 만들기
//
//   swift scripts/make-table-samples.swift [출력 폴더, 기본 Tests/OCRSamples/tables]
//
// 화면 캡처처럼 표를 그려 <이름>.png와 정답 <이름>.tsv(탭으로 나눈 칸)를 만든다.
// 실제 캡처를 넣고 싶으면 같은 폴더에 <이름>.png + <이름>.tsv를 두면 측정에 함께 들어간다.
import AppKit

struct TableSample {
    let name: String
    let rows: [[String]]
    var font = "AppleSDGothicNeo-Regular"
    var size: CGFloat = 14
    var scale: CGFloat = 2
    /// 칸마다 선 (false면 엑셀처럼 옅은 선만, 또는 줄무늬)
    var grid = true
    var stripes = false
    var dark = false
}

let samples: [TableSample] = [
    TableSample(name: "ko-grid", rows: [
        ["이름", "부서", "입사일", "내선"],
        ["김민준", "개발팀", "2021-03-02", "4021"],
        ["이서연", "디자인팀", "2022-07-18", "4107"],
        ["박지호", "영업팀", "2019-11-04", "4310"],
    ]),
    TableSample(name: "mixed-numbers", rows: [
        ["품목", "수량", "단가", "합계"],
        ["MacBook Air 13", "2", "1,590,000", "3,180,000"],
        ["USB-C 케이블", "10", "19,000", "190,000"],
        ["모니터 27\"", "3", "450,000", "1,350,000"],
        ["합계", "", "", "4,720,000"],
    ]),
    TableSample(name: "sheet-light", rows: [
        ["날짜", "방문자", "전환율", "비고"],
        ["10/27", "1,204", "3.2%", "주말"],
        ["10/28", "2,881", "4.1%", "광고 시작"],
        ["10/29", "3,016", "4.4%", ""],
    ], grid: false),
    TableSample(name: "stripes-en", rows: [
        ["Module", "Version", "Status"],
        ["Capture", "0.2.0", "Done"],
        ["OCR", "0.3.0", "Done"],
        ["Clipboard", "0.4.0", "In progress"],
        ["Organize", "0.6.0", "Planned"],
    ], font: "HelveticaNeue", grid: false, stripes: true),
    TableSample(name: "dark-grid", rows: [
        ["항목", "켜짐", "단축키"],
        ["영역 캡처", "예", "⌃⇧1"],
        ["텍스트 추출", "예", "⌃⇧2"],
        ["클립보드", "아니요", "⇧⌘V"],
    ], dark: true),
    // 외장 모니터 등 1배율 화면의 작은 글자
    TableSample(name: "ko-small-1x", rows: [
        ["지역", "1분기", "2분기", "3분기"],
        ["서울", "12,400", "13,050", "14,210"],
        ["부산", "6,320", "6,108", "6,775"],
        ["대전", "3,010", "3,240", "3,198"],
    ], size: 11, scale: 1),
]

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/OCRSamples/tables", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for s in samples {
    let font = NSFont(name: s.font, size: s.size) ?? NSFont.systemFont(ofSize: s.size)
    let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    let fg: NSColor = s.dark ? .white : .black
    let line: NSColor = s.dark ? NSColor(white: 0.4, alpha: 1) : NSColor(white: s.grid ? 0.55 : 0.85, alpha: 1)
    let bg: NSColor = s.dark ? NSColor(white: 0.12, alpha: 1) : .white
    let padX: CGFloat = 12, rowHeight = s.size * 2.2, margin: CGFloat = 16
    let columnWidths = (0..<s.rows[0].count).map { c in
        s.rows.map { NSAttributedString(string: $0[c], attributes: [.font: bold]).size().width }.max()! + padX * 2
    }
    let size = NSSize(width: columnWidths.reduce(0, +) + margin * 2, height: rowHeight * CGFloat(s.rows.count) + margin * 2)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * s.scale), pixelsHigh: Int(size.height * s.scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("bitmap") }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    bg.setFill()
    NSRect(origin: .zero, size: size).fill()
    for (r, row) in s.rows.enumerated() {
        let y = size.height - margin - rowHeight * CGFloat(r + 1)
        if s.stripes && r % 2 == 1 {
            NSColor(white: 0.94, alpha: 1).setFill()
            NSRect(x: margin, y: y, width: size.width - margin * 2, height: rowHeight).fill()
        }
        var x = margin
        for (c, text) in row.enumerated() {
            let attributed = NSAttributedString(string: text, attributes: [.font: r == 0 ? bold : font, .foregroundColor: fg])
            attributed.draw(at: NSPoint(x: x + padX, y: y + (rowHeight - attributed.size().height) / 2))
            x += columnWidths[c]
        }
        line.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: margin, y: y))
        path.line(to: NSPoint(x: size.width - margin, y: y))
        if r == 0 {
            path.move(to: NSPoint(x: margin, y: y + rowHeight))
            path.line(to: NSPoint(x: size.width - margin, y: y + rowHeight))
        }
        path.stroke()
    }
    if s.grid {
        let path = NSBezierPath()
        var x = margin
        for w in [0] + columnWidths {
            x += w
            path.move(to: NSPoint(x: x, y: margin))
            path.line(to: NSPoint(x: x, y: size.height - margin))
        }
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(s.name + ".png"))
    try (s.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n") + "\n")
        .write(to: out.appendingPathComponent(s.name + ".tsv"), atomically: true, encoding: .utf8)
    print("\(s.name).png  \(rep.pixelsWide)×\(rep.pixelsHigh)")
}
