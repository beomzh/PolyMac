// OCR 측정용 합성 샘플 만들기 (docs/ROADMAP.md 0.3.0 "한글 OCR 정확도 샘플셋")
//
//   swift scripts/make-ocr-samples.swift [출력 폴더, 기본 Tests/OCRSamples]
//
// 화면 캡처처럼 글자를 그려 <이름>.png와 정답 <이름>.txt를 만든다. 실제 캡처를 넣고 싶으면
// 같은 폴더에 <이름>.png + <이름>.txt(정답)를 두면 측정에 함께 들어간다.
import AppKit

struct Sample {
    let name: String
    let text: String
    var font = "AppleSDGothicNeo-Regular"
    var size: CGFloat = 15
    /// 2 = 레티나 캡처, 1 = 일반 화면(작은 글자가 몇 픽셀뿐)
    var scale: CGFloat = 2
    var foreground = NSColor.black
    var background = NSColor.white
    var width: CGFloat = 640
}

let gray = NSColor(white: 0.45, alpha: 1)
let samples: [Sample] = [
    Sample(name: "ko-body", text: "자동 정리 규칙은 위에서부터 차례대로 검사합니다. 조건이 모두 맞으면 동작을 실행합니다."),
    Sample(name: "ko-small-1x", text: "환경 설정에서 단축키를 바꾸거나 지울 수 있습니다. 바꾼 단축키는 바로 적용됩니다.", size: 11, scale: 1),
    Sample(name: "ko-paragraph", text: "클립보드 기록은 암호화해 저장합니다.\n키는 디스크가 아니라 로그인 키체인에 있고,\n같은 인증서로 서명된 앱만 꺼낼 수 있습니다."),
    Sample(name: "mixed-ko-en", text: "macOS 14 Sonoma 이상에서 PolyMac 0.1.0을 설치하세요 (Apple Silicon·Intel 모두 지원)."),
    Sample(name: "numbers", text: "주문번호 2026-10-29-0042, 금액 1,234,500원, 전화 010-1234-5678"),
    Sample(name: "url-email", text: "자세한 내용은 https://github.com/beomzh/PolyMac 또는 help@example.com 으로 문의하세요."),
    Sample(name: "code-mono", text: "let total = items.filter { $0.isPinned }.count // 고정 개수", font: "Menlo-Regular", size: 13),
    Sample(name: "dark-mode", text: "다크 모드에서도 글자를 정확하게 읽어야 합니다.", foreground: .white, background: NSColor(white: 0.12, alpha: 1)),
    Sample(name: "low-contrast", text: "회색 보조 설명: 기능이 꺼져 있으면 저장만 됩니다.", size: 12, foreground: gray, background: NSColor(white: 0.93, alpha: 1)),
    Sample(name: "symbols", text: "괄호 [대괄호] {중괄호} 「낫표」 — 줄표 · 가운뎃점 … 말줄임 ※ 참고"),
    Sample(name: "address", text: "서울특별시 강남구 테헤란로 152, 강남파이낸스센터 20층"),
    Sample(name: "english", text: "The quick brown fox jumps over the lazy dog. Version 2.4.1 (build 1187)", font: "HelveticaNeue"),
    // 큰 캡처 (약 2000×1700 px) — 정확도와 함께 키워 읽을 때 걸리는 시간을 본다
    Sample(name: "ko-long", text: (1...3).map { n in
        "\(n)번째 문단입니다. 다운로드 폴더에 쌓인 파일은 규칙에 따라 자동으로 정리됩니다. 처음 켜면 미리보기 모드라 실제로 옮기지 않고 계획만 보여 줍니다. 확인한 뒤 미리보기를 끄면 그때부터 옮깁니다. 같은 이름이 있으면 덮어쓰지 않고 번호를 붙여 저장합니다."
    }.joined(separator: "\n\n"), size: 17, width: 1000),
    Sample(name: "system-ui", text: "알림 보이기 · 위치: 오른쪽 위 · 표시 시간 2.5초", font: ".AppleSystemUIFont", size: 13),
]

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/OCRSamples", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for s in samples {
    let font = NSFont(name: s.font, size: s.size) ?? NSFont.systemFont(ofSize: s.size)
    let style = NSMutableParagraphStyle()
    style.lineSpacing = s.size * 0.35
    let attributed = NSAttributedString(string: s.text, attributes: [.font: font, .foregroundColor: s.foreground, .paragraphStyle: style])
    let pad: CGFloat = 16
    let bounds = attributed.boundingRect(with: NSSize(width: s.width - pad * 2, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let size = NSSize(width: s.width, height: ceil(bounds.height) + pad * 2)
    let pixelsWide = Int(size.width * s.scale), pixelsHigh = Int(size.height * s.scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("bitmap") }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    s.background.setFill()
    NSRect(origin: .zero, size: size).fill()
    attributed.draw(with: NSRect(x: pad, y: pad, width: s.width - pad * 2, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(s.name + ".png"))
    try (s.text + "\n").write(to: out.appendingPathComponent(s.name + ".txt"), atomically: true, encoding: .utf8)
    print("\(s.name): \(pixelsWide)x\(pixelsHigh)")
}
