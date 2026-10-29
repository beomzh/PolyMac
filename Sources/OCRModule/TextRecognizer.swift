import AppKit
import PolyMacCore
import Vision

/// Apple Vision 온디바이스 OCR. 네트워크를 쓰지 않는다.
public enum TextRecognizer {
    /// QR·바코드 내용이 있으면 먼저, 그 뒤에 인식한 글자를 줄 단위로.
    public static func recognize(_ image: CGImage, languages: [String] = ["ko-KR", "en-US"],
                                 lineMode: OCRLineMode = .current) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.recognitionLanguages = languages
                textRequest.usesLanguageCorrection = true
                let barcodeRequest = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([textRequest, barcodeRequest])
                    let codes = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue)
                    let lines = (textRequest.results ?? []).compactMap { observation in
                        observation.topCandidates(1).first.map { LineJoiner.Line(text: $0.string, box: observation.boundingBox) }
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
}

@MainActor
public enum OCRRunner {
    /// 인식 → NFC 정규화 → 클립보드 → 미리보기 안내
    public static func recognizeAndCopy(_ image: CGImage) async {
        do {
            let text = try await TextRecognizer.recognize(image).precomposedStringWithCanonicalMapping
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Toast.show(L("글자를 찾지 못했습니다", "No text found"))
                return
            }
            PasteboardWriter.copy(text, origin: .ocr)
            let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text
            Toast.show(L("텍스트를 클립보드에 복사했습니다", "Text copied to the clipboard"), content: preview, duration: 3)
        } catch {
            Toast.show(L("텍스트 추출 실패: \(error.localizedDescription)", "Text recognition failed: \(error.localizedDescription)"))
        }
    }
}
