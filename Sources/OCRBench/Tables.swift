// 표 인식 측정 (scripts/ocr-bench.sh --tables). 샘플 폴더의 <이름>.png를 읽어 <이름>.tsv(정답)와 칸 단위로 비교한다.
import AppKit
import OCRModule

func runTableBench(folder: URL, verbose: Bool) async throws {
    guard TableRecognizer.isAvailable else { print("표 인식은 macOS 26 이상에서만 됩니다"); exit(1) }
    let configs: [Config] = [
        Config(name: "app", options: TableRecognizer.defaultOptions),
        Config(name: "upscale-2x", options: OCROptions()),
        Config(name: "no-cleanup", options: option { $0.upscale = 1; $0.cleanup = false }),
    ]
    let names = (try FileManager.default.contentsOfDirectory(atPath: folder.path))
        .filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
        .filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0 + ".tsv").path) }
    guard let first = names.first,
          let warm = NSImage(contentsOf: folder.appendingPathComponent(first + ".png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { print("샘플이 없습니다: \(folder.path)"); exit(1) }
    for config in configs { _ = try await TableRecognizer.recognize(warm, options: config.options) }

    // 칸 정확도 = 정답과 글자가 같은 칸 / 정답 칸, 모양 = 행·열 수가 맞은 샘플
    var totals = [String: (cells: Int, right: Int, errors: Int, chars: Int, shape: Int, seconds: Double)]()
    print("sample".padding(toLength: 16, withPad: " ", startingAt: 0) + configs.map { $0.name.padding(toLength: 22, withPad: " ", startingAt: 0) }.joined())
    for name in names {
        let truthText = try String(contentsOf: folder.appendingPathComponent(name + ".tsv"), encoding: .utf8)
        let truth = TableGrid(rows: truthText.split(separator: "\n", omittingEmptySubsequences: true).map { $0.components(separatedBy: "\t") })
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(name + ".png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        var row = name.padding(toLength: 16, withPad: " ", startingAt: 0)
        var notes: [String] = []
        for config in configs {
            let start = Date()
            let got = try await TableRecognizer.recognize(image, options: config.options).first ?? TableGrid(rows: [])
            let seconds = Date().timeIntervalSince(start)
            var t = totals[config.name] ?? (0, 0, 0, 0, 0, 0)
            var right = 0
            for (r, cells) in truth.rows.enumerated() {
                for (c, want) in cells.enumerated() {
                    let have = r < got.rows.count && c < got.columnCount ? got.rows[r][c] : ""
                    if normalize(have) == normalize(want) { right += 1 }
                    t.errors += distance(normalize(want), normalize(have))
                    t.chars += max(normalize(want).count, 1)
                }
            }
            let cells = truth.rows.count * truth.columnCount
            let shape = got.rows.count == truth.rows.count && got.columnCount == truth.columnCount
            t.cells += cells; t.right += right; t.shape += shape ? 1 : 0; t.seconds += seconds
            totals[config.name] = t
            row += "\(right)/\(cells) \(got.rows.count)×\(got.columnCount)\(shape ? "" : "!")".padding(toLength: 22, withPad: " ", startingAt: 0)
            if verbose && (right < cells || !shape) { notes.append("    [\(config.name)]\n" + got.tsv.split(separator: "\n").map { "      " + $0 }.joined(separator: "\n")) }
        }
        print(row)
        if !notes.isEmpty { print(notes.joined(separator: "\n")) }
    }
    print("")
    func line(_ title: String, _ value: (String) -> String) {
        print(title.padding(toLength: 16, withPad: " ", startingAt: 0) + configs.map { value($0.name).padding(toLength: 22, withPad: " ", startingAt: 0) }.joined())
    }
    line("cells right") { n in let t = totals[n]!; return String(format: "%.1f%%", Double(t.right) / Double(t.cells) * 100) }
    line("cell CER") { n in let t = totals[n]!; return String(format: "%.2f%%", Double(t.errors) / Double(t.chars) * 100) }
    line("shape") { n in "\(totals[n]!.shape)/\(names.count)" }
    line("avg ms") { n in String(format: "%.0f", totals[n]!.seconds / Double(names.count) * 1000) }
}
