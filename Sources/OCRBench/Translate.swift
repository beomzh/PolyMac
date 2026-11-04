// 인식 → 번역 결과 보기 (앱과 같은 조각 나누기). scripts/ocr-bench.sh --translate
import AppKit
import OCRModule
import Translation

func runTranslate(folder: URL) async throws {
    guard #available(macOS 26.0, *) else { print("macOS 26 이상에서 됩니다"); return }
    let names = (try FileManager.default.contentsOfDirectory(atPath: folder.path)).filter { $0.hasSuffix(".png") }.sorted()
    for name in names {
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let text = try await TextRecognizer.recognize(image, lineMode: .paragraphs).precomposedStringWithCanonicalMapping
        let source = TranslationDirection.source(of: text)
        let target = TranslationDirection.target(source: source, preferred: "ko")
        guard ["ko", "en"].contains(String(source.prefix(2))) else { print("== \(name): \(source) 건너뜀"); continue }
        let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
        let blocks = TranslationText.blocks(text)
        let requests = blocks.enumerated().filter { !$0.element.body.isEmpty }
            .map { TranslationSession.Request(sourceText: $0.element.body, clientIdentifier: String($0.offset)) }
        var translated: [Int: String] = [:]
        for response in try await session.translations(from: requests) {
            if let index = response.clientIdentifier.flatMap(Int.init) { translated[index] = response.targetText }
        }
        print("== \(name) \(source)->\(target)\n[원문]\n\(text)\n[번역]\n\(TranslationText.rebuild(blocks, translated: translated))\n")
    }
}
