import AppKit
import PolyMacCore
import Vision

/// 인식 설정. 기본값이 앱에서 쓰는 값이고, 측정 도구(scripts/ocr-bench.sh)가 바꿔 가며 비교한다.
/// 측정 결과(합성 샘플 14개, docs/OCR-BENCH.md): 예전 설정 글자 오류율 1.58% → 지금 0.93%, 정확히 맞힌 샘플 9 → 11개.
public struct OCROptions: Sendable {
    /// 한국어가 앞이어야 한다 — 영어를 앞에 두면 한글을 거의 못 읽는다 (오류율 62%)
    public var languages = ["ko-KR", "en-US"]
    public var languageCorrection = true
    /// 이미지를 이만큼 키워서 읽는다. 줄 첫 글자를 빠뜨리거나 기호를 잘못 읽는 일이 줄었다 (1 = 그대로).
    /// 이미 큰 캡처(upscaleMaxPixels 넘음)는 키우지 않는다 — 큰 글자엔 도움이 없고 시간만 든다 (2000×1870에서 +0.24초).
    public var upscale: CGFloat = 2
    public var upscaleMaxPixels = 2_000_000
    /// 흔한 기호 오인식 고치기 (OCRCleanup)
    public var cleanup = true

    public init() {}
}

/// Apple Vision 온디바이스 OCR. 네트워크를 쓰지 않는다.
public enum TextRecognizer {
    /// QR·바코드 내용이 있으면 먼저, 그 뒤에 인식한 글자를 줄 단위로.
    public static func recognize(_ image: CGImage, options: OCROptions = OCROptions(),
                                 lineMode: OCRLineMode = .current) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.recognitionLanguages = options.languages
                textRequest.usesLanguageCorrection = options.languageCorrection
                let barcodeRequest = VNDetectBarcodesRequest()
                let factor = image.width * image.height <= options.upscaleMaxPixels ? options.upscale : 1
                let handler = VNImageRequestHandler(cgImage: scaled(image, by: factor), options: [:])
                do {
                    try handler.perform([textRequest, barcodeRequest])
                    let codes = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue)
                    // 기호 정리는 줄을 잇기 전에 — 이은 뒤에 하면 줄 맨 앞 글머리표가 줄 가운데로 와서 가운뎃점이 된다
                    let lines = (textRequest.results ?? []).compactMap { observation in
                        observation.topCandidates(1).first.map {
                            LineJoiner.Line(text: options.cleanup ? OCRCleanup.fixLine($0.string) : $0.string, box: observation.boundingBox)
                        }
                    }
                    var parts = codes
                    if !lines.isEmpty { parts.append(LineJoiner.join(lines, mode: lineMode)) }
                    continuation.resume(returning: parts.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 고품질 보간으로 키운다
    static func scaled(_ image: CGImage, by factor: CGFloat) -> CGImage {
        guard factor > 1 else { return image }
        let width = Int(CGFloat(image.width) * factor), height = Int(CGFloat(image.height) * factor)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }
}

@MainActor
public enum OCRRunner {
    /// 인식 → NFC 정규화 → 클립보드 → 미리보기 안내
    /// 돌려주는 값: 클립보드에 넣었는지 (단축어에 성공·실패를 알릴 때 쓴다)
    @discardableResult
    public static func recognizeAndCopy(_ image: CGImage) async -> Bool {
        do {
            let text = try await TextRecognizer.recognize(image).precomposedStringWithCanonicalMapping
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Toast.show(L("글자를 찾지 못했습니다", "No text found"))
                return false
            }
            PasteboardWriter.copy(text, origin: .ocr)
            let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text
            Toast.show(L("텍스트를 클립보드에 복사했습니다", "Text copied to the clipboard"), content: preview, duration: 3)
            return true
        } catch {
            Toast.show(L("텍스트 추출 실패: \(error.localizedDescription)", "Text recognition failed: \(error.localizedDescription)"))
            return false
        }
    }

    /// 표 인식 → 표 형식에 따라 TSV(+ 서식 앱용 HTML 표) 또는 Markdown. 표가 없으면 일반 텍스트로.
    @discardableResult
    public static func recognizeTableAndCopy(_ image: CGImage, format: TableFormat = .current) async -> Bool {
        guard TableRecognizer.isAvailable else {
            Toast.show(L("표 인식은 macOS 26 이상에서 됩니다 — 일반 텍스트로 복사합니다", "Table recognition needs macOS 26 or later — copying as plain text"))
            return await recognizeAndCopy(image)
        }
        do {
            let tables = try await TableRecognizer.recognize(image)
            guard !tables.isEmpty else {
                Toast.show(L("표를 찾지 못해 일반 텍스트로 복사합니다", "No table found — copying as plain text"))
                return await recognizeAndCopy(image)
            }
            let text = tables.map { $0.text(format) }.joined(separator: "\n\n")
            if format == .tsv {
                PasteboardWriter.copy(text, html: tables.map(\.html).joined(separator: "<br>"), origin: .ocr)
            } else {
                PasteboardWriter.copy(text, origin: .ocr)
            }
            let shape = tables.map { "\($0.rows.count)×\($0.columnCount)" }.joined(separator: ", ")
            let title = format == .tsv
                ? L("표(\(shape))를 복사했습니다 — 엑셀·Numbers·구글 시트에 붙여넣기", "Copied the table (\(shape)) — paste into Excel, Numbers or Sheets")
                : L("표(\(shape))를 Markdown으로 복사했습니다", "Copied the table (\(shape)) as Markdown")
            Toast.show(title, content: text.count > 160 ? String(text.prefix(160)) + "…" : text, duration: 3)
            return true
        } catch {
            Toast.show(L("표 인식 실패: \(error.localizedDescription)", "Table recognition failed: \(error.localizedDescription)"))
            return false
        }
    }
}
