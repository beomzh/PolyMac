import AppIntents
import AppKit
import NormalizeModule
import OCRModule
import PolyMacCore
import os

// 단축어(Shortcuts) 앱의 동작 목록에 뜨는 PolyMac 동작. 결과는 단축어로 돌려주고 클립보드는 건드리지 않는다.
// polymac:// URL과 달리 웹 페이지가 부를 수 없어(단축어·Spotlight에서 사용자가 만든 흐름만) 따로 허용하지 않아도 된다.
// 기능을 꺼 두었으면 동작하지 않는다. 메타데이터(Metadata.appintents)는 scripts/build-app.sh가 Xcode 도구로 만든다.

private let intentLogger = Logger(subsystem: "dev.polymac", category: "intents")

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }

    static func moduleOff(_ name: String) -> IntentFailure {
        IntentFailure(message: L("PolyMac의 '\(name)' 기능이 꺼져 있습니다 — 메뉴바 › 환경 설정에서 켜세요",
                                 "PolyMac's '\(name)' feature is off — turn it on in menu bar › Settings"))
    }
}

@MainActor
enum IntentSupport {
    static func requireModule(_ id: String, _ name: String) throws {
        guard (NSApp.delegate as? AppDelegate)?.isActive(id) == true else {
            intentLogger.notice("intent refused: module \(id, privacy: .public) is off")
            throw IntentFailure.moduleOff(name)
        }
    }

    /// 넘겨받은 파일 → 없으면 클립보드 이미지
    static func image(_ file: IntentFile?) throws -> CGImage {
        if let file {
            guard let source = CGImageSourceCreateWithData(file.data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw IntentFailure(message: L("이미지를 읽지 못했습니다", "Could not read the image")) }
            return image
        }
        guard let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw IntentFailure(message: L("이미지를 넘기거나 클립보드에 이미지를 넣어 주세요", "Pass an image or put one on the clipboard"))
        }
        return image
    }

    static func text(_ image: CGImage) async throws -> String {
        let text = try await TextRecognizer.recognize(image).precomposedStringWithCanonicalMapping
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntentFailure(message: L("글자를 찾지 못했습니다", "No text found"))
        }
        return text
    }
}

struct ExtractTextIntent: AppIntent {
    static let title: LocalizedStringResource = "이미지에서 텍스트 추출"
    static let description = IntentDescription("이미지의 글자와 QR 코드를 읽습니다. 이미지를 넘기지 않으면 클립보드 이미지를 읽습니다. 기기 안에서만 처리합니다.")

    @Parameter(title: "이미지", supportedTypeIdentifiers: ["public.image"])
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try IntentSupport.requireModule("ocr", L("텍스트 추출", "Text Recognition"))
        let text = try await IntentSupport.text(try IntentSupport.image(image))
        intentLogger.info("extract text: \(text.count) chars")
        return .result(value: text)
    }
}

enum IntentTableFormat: String, AppEnum {
    case tsv, markdown

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "표 형식"
    static let caseDisplayRepresentations: [IntentTableFormat: DisplayRepresentation] = [
        .tsv: "엑셀·Numbers (탭으로 나눔)",
        .markdown: "Markdown 표",
    ]
}

struct ExtractTableIntent: AppIntent {
    static let title: LocalizedStringResource = "이미지에서 표 추출"
    static let description = IntentDescription("이미지의 표를 칸마다 나눈 글로 돌려줍니다 (macOS 26 이상). 표가 없거나 이전 macOS면 일반 텍스트로 돌려줍니다.")

    @Parameter(title: "이미지", supportedTypeIdentifiers: ["public.image"])
    var image: IntentFile?

    @Parameter(title: "형식", default: .tsv)
    var format: IntentTableFormat

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try IntentSupport.requireModule("ocr", L("텍스트 추출", "Text Recognition"))
        let cg = try IntentSupport.image(image)
        let tables = TableRecognizer.isAvailable ? try await TableRecognizer.recognize(cg) : []
        guard !tables.isEmpty else { return .result(value: try await IntentSupport.text(cg)) }
        let tableFormat: TableFormat = format == .tsv ? .tsv : .markdown
        intentLogger.info("extract table: \(tables.count) tables")
        return .result(value: tables.map { $0.text(tableFormat) }.joined(separator: "\n\n"))
    }
}

struct CaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "화면 영역에서 텍스트 추출"
    static let description = IntentDescription("화면에서 영역을 골라 글자를 읽습니다. 화면 녹음 권한이 필요합니다.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try IntentSupport.requireModule("ocr", L("텍스트 추출", "Text Recognition"))
        guard let capture = await RegionCapture.selectRegion() else {
            throw IntentFailure(message: L("영역 선택을 취소했습니다", "Selection cancelled"))
        }
        return .result(value: try await IntentSupport.text(capture.image))
    }
}

struct FixHangulIntent: AppIntent {
    static let title: LocalizedStringResource = "풀어진 한글 붙이기"
    static let description = IntentDescription("Mac에서 받은 파일명·글처럼 자음·모음이 풀어진 한글(NFD)을 붙인 글(NFC)로 바꿉니다.")

    @Parameter(title: "글")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: HangulNormalizer.composeHangul(text) ?? text)
    }
}
