// OCR 정확도 측정 (개발용, 앱에는 들어가지 않는다). scripts/ocr-bench.sh로 실행.
//
// 샘플 폴더의 <이름>.png를 읽어 <이름>.txt(정답)와 비교한다. 글자 오류율(CER) =
// 편집 거리 / 정답 글자 수. 비교 전에 NFC로 맞추고 공백·줄바꿈은 한 칸으로 본다.
import AppKit
import OCRModule

struct Config {
    let name: String
    let options: OCROptions
}

func normalize(_ s: String) -> [Character] {
    Array(s.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " "))
}

func distance(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    var previous = Array(0...b.count)
    for (i, x) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, y) in b.enumerated() {
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
        }
        previous = current
    }
    return previous[b.count]
}

func option(_ change: (inout OCROptions) -> Void) -> OCROptions {
    var o = OCROptions()
    change(&o)
    return o
}

let args = CommandLine.arguments.dropFirst()
let folder = URL(fileURLWithPath: args.first { !$0.hasPrefix("-") } ?? "Tests/OCRSamples", isDirectory: true)
let verbose = args.contains("-v")
if args.contains("--tables") {
    let tables = URL(fileURLWithPath: args.first { !$0.hasPrefix("-") } ?? "Tests/OCRSamples/tables", isDirectory: true)
    try await runTableBench(folder: tables, verbose: verbose)
    exit(0)
}
// 다른 설정을 시험하려면 여기에 더한다
let configs: [Config] = [
    Config(name: "app", options: OCROptions()),
    Config(name: "0.1.0", options: option { $0.upscale = 1; $0.cleanup = false }),
    Config(name: "no-upscale", options: option { $0.upscale = 1 }),
    Config(name: "no-cleanup", options: option { $0.cleanup = false }),
]

let names = (try FileManager.default.contentsOfDirectory(atPath: folder.path))
    .filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
    .filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0 + ".txt").path) }
guard !names.isEmpty else { print("샘플이 없습니다: \(folder.path)"); exit(1) }

// Vision 모델을 처음 불러오는 시간이 첫 설정에만 붙지 않게 한 번 먼저 돌린다
if let first = names.first,
   let warm = NSImage(contentsOf: folder.appendingPathComponent(first + ".png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    for config in configs { _ = try await TextRecognizer.recognize(warm, options: config.options, lineMode: .keep) }
}

var totals = [String: (errors: Int, chars: Int, exact: Int, seconds: Double)]()
print("sample".padding(toLength: 16, withPad: " ", startingAt: 0) + configs.map { $0.name.padding(toLength: 15, withPad: " ", startingAt: 0) }.joined())
for name in names {
    let truth = normalize(try String(contentsOf: folder.appendingPathComponent(name + ".txt"), encoding: .utf8))
    guard let image = NSImage(contentsOf: folder.appendingPathComponent(name + ".png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    var row = name.padding(toLength: 16, withPad: " ", startingAt: 0)
    var misses: [String] = []
    for config in configs {
        let start = Date()
        let text = try await TextRecognizer.recognize(image, options: config.options, lineMode: .keep)
        let seconds = Date().timeIntervalSince(start)
        let got = normalize(text)
        let errors = distance(truth, got)
        var t = totals[config.name] ?? (0, 0, 0, 0)
        t.errors += errors; t.chars += truth.count; t.exact += errors == 0 ? 1 : 0; t.seconds += seconds
        totals[config.name] = t
        row += String(format: "%5.1f%%", Double(errors) / Double(max(truth.count, 1)) * 100).padding(toLength: 15, withPad: " ", startingAt: 0)
        if verbose && errors > 0 { misses.append("    [\(config.name)] \(String(got))") }
    }
    print(row)
    if !misses.isEmpty { print("    정답        \(String(truth))\n" + misses.joined(separator: "\n")) }
}
print("")
print("total CER".padding(toLength: 16, withPad: " ", startingAt: 0) + configs.map { c in
    let t = totals[c.name]!
    return String(format: "%5.2f%%", Double(t.errors) / Double(t.chars) * 100).padding(toLength: 15, withPad: " ", startingAt: 0)
}.joined())
print("exact".padding(toLength: 16, withPad: " ", startingAt: 0) + configs.map { c in
    "\(totals[c.name]!.exact)/\(names.count)".padding(toLength: 15, withPad: " ", startingAt: 0)
}.joined())
print("avg ms".padding(toLength: 16, withPad: " ", startingAt: 0) + configs.map { c in
    String(format: "%.0f", totals[c.name]!.seconds / Double(names.count) * 1000).padding(toLength: 15, withPad: " ", startingAt: 0)
}.joined())
