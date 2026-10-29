import AppKit
import PolyMacCore
import Vision

/// 표를 복사할 때의 글 형식. 엑셀·Numbers·구글 시트는 탭으로 나눈 글(TSV)을 칸마다 나눠 붙인다.
public enum TableFormat: String, CaseIterable, Sendable {
    case tsv, markdown

    static let defaultsKey = "ocr.tableFormat"

    public static var current: TableFormat {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(TableFormat.init(rawValue:)) ?? .tsv }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// 칸 글자를 행·열 격자로. 합쳐진 칸은 맨 왼쪽 위 칸에만 글자를 두고 나머지는 비운다 (엑셀에 붙였을 때 줄이 밀리지 않게).
public struct TableGrid: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        public var rows: ClosedRange<Int>
        public var columns: ClosedRange<Int>
        public var text: String

        public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>, text: String) {
            self.rows = rows
            self.columns = columns
            self.text = text
        }
    }

    public private(set) var rows: [[String]]

    public init(rows: [[String]]) {
        let width = rows.map(\.count).max() ?? 0
        self.rows = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    public init(cells: [Cell]) {
        let height = (cells.map(\.rows.upperBound).max() ?? -1) + 1
        let width = (cells.map(\.columns.upperBound).max() ?? -1) + 1
        var rows = Array(repeating: Array(repeating: "", count: width), count: height)
        for cell in cells where cell.rows.lowerBound >= 0 && cell.columns.lowerBound >= 0 {
            let r = cell.rows.lowerBound, c = cell.columns.lowerBound
            // 같은 칸이 두 번 오면 (합친 칸이 행마다 되풀이되는 경우) 처음 것만
            if rows[r][c].isEmpty { rows[r][c] = cell.text }
        }
        self.init(rows: rows)
    }

    public var columnCount: Int { rows.first?.count ?? 0 }
    public var isEmpty: Bool { rows.allSatisfy { $0.allSatisfy(\.isEmpty) } }

    /// 칸 안의 줄바꿈·탭은 칸을 나누는 기호라 한 칸으로 바꾼다
    private static func flatten(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    public var tsv: String {
        rows.map { $0.map(Self.flatten).joined(separator: "\t") }.joined(separator: "\n")
    }

    /// 첫 행을 머리글로 본다
    public var markdown: String {
        guard !rows.isEmpty else { return "" }
        func line(_ cells: [String]) -> String {
            "| " + cells.map { Self.flatten($0).replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        var lines = [line(rows[0]), "|" + Array(repeating: " --- |", count: columnCount).joined()]
        lines += rows.dropFirst().map(line)
        return lines.joined(separator: "\n")
    }

    /// Pages·메모·메일처럼 서식을 받는 앱에는 진짜 표로 들어가게
    public var html: String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let body = rows.map { "<tr>" + $0.map { "<td>\(escape(Self.flatten($0)))</td>" }.joined() + "</tr>" }.joined()
        return "<meta charset=\"utf-8\"><table>\(body)</table>"
    }

    public func text(_ format: TableFormat) -> String {
        format == .tsv ? tsv : markdown
    }
}

/// Apple Vision 문서 인식(macOS 26)으로 표를 찾는다. 기기 안에서만 돈다.
public enum TableRecognizer {
    public static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 표는 키워 읽어도 나아지지 않고 시간만 든다 (표 샘플 6개에서 칸 정확도 같음, 218 → 264 ms — docs/OCR-BENCH.md)
    public static var defaultOptions: OCROptions {
        var options = OCROptions()
        options.upscale = 1
        return options
    }

    /// 찾은 표들 (위에서 아래 순서). 표가 없으면 빈 배열.
    public static func recognize(_ image: CGImage, options: OCROptions = defaultOptions) async throws -> [TableGrid] {
        guard #available(macOS 26.0, *) else { return [] }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = options.languages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.useLanguageCorrection = options.languageCorrection
        request.barcodeDetectionOptions.enabled = false
        let factor = image.width * image.height <= options.upscaleMaxPixels ? options.upscale : 1
        let documents = try await request.perform(on: TextRecognizer.scaled(image, by: factor))
        let tables = documents.flatMap(\.document.tables)
            .sorted { $0.boundingRegion.boundingBox.origin.y > $1.boundingRegion.boundingBox.origin.y }
        return tables.map { table in
            let cells = table.rows.flatMap { $0 }.map { cell in
                let text = cell.content.text.transcript.precomposedStringWithCanonicalMapping
                return TableGrid.Cell(rows: cell.rowRange, columns: cell.columnRange,
                                      text: options.cleanup ? OCRCleanup.fixLine(text) : text)
            }
            return TableGrid(cells: cells)
        }.filter { !$0.isEmpty }
    }
}
