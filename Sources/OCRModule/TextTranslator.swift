import AppKit
import NaturalLanguage
import PolyMacCore
import SwiftUI
import Translation
import os

/// 어느 언어에서 어느 언어로 옮길지. 내 언어가 아닌 글은 내 언어로, 내 언어로 된 글은 영어로 (영어가 내 언어면 한국어로).
public enum TranslationDirection {
    /// 글의 주 언어. 언어 판별기는 짧은 글이나 웹 주소·영어 낱말이 섞인 한글을 다른 언어로 보기 쉬워 한글 비율을 먼저 본다.
    public static func source(of text: String) -> String {
        let sample = String(text.prefix(2000))
        let letters = sample.unicodeScalars.filter(CharacterSet.letters.contains)
        let hangul = letters.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        if hangul * 5 >= letters.count, hangul > 0 { return "ko" }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = [.english: 0.7, .korean: 0.1, .japanese: 0.1, .simplifiedChinese: 0.1]
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    public static func target(source: String, preferred: String) -> String {
        guard base(source) == base(preferred) else { return preferred }
        return base(preferred) == "en" ? "ko" : "en"
    }

    /// 시스템 첫 번째 언어 ("ko-KR" → "ko")
    public static var preferred: String {
        base(Locale.preferredLanguages.first ?? "en")
    }

    private static func base(_ identifier: String) -> String {
        String(identifier.split(separator: "-").first ?? "en").lowercased()
    }
}

/// Apple Translation 온디바이스 번역 (macOS 15+). 글은 기기 밖으로 나가지 않는다.
/// 언어 모델이 없으면 macOS가 내려받기 창을 띄우고, 받는 일도 시스템이 한다 — docs/SECURITY.md
public enum TextTranslator {
    public static var isAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// 번역문과 쓴 언어
    public static func translate(_ text: String) async throws -> (text: String, source: String, target: String) {
        guard #available(macOS 15.0, *) else { throw TranslationFailure.unavailable }
        let source = TranslationDirection.source(of: text)
        let target = TranslationDirection.target(source: source, preferred: TranslationDirection.preferred)
        let from = Locale.Language(identifier: source), to = Locale.Language(identifier: target)
        let status = await LanguageAvailability().status(from: from, to: to)
        guard status != .unsupported else { throw TranslationFailure.unsupported(source, target) }
        let translated = try await TranslationHost.run(text, from: from, to: to, needsDownload: status != .installed)
        return (translated, source, target)
    }
}

enum TranslationFailure: LocalizedError {
    case unavailable, cancelled, unsupported(String, String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return L("번역은 macOS 15 이상에서 됩니다", "Translation needs macOS 15 or later")
        case .cancelled: return L("취소했습니다", "Cancelled")
        case .unsupported(let source, let target):
            return L("\(source) → \(target) 번역은 지원하지 않습니다", "\(source) to \(target) is not supported")
        }
    }
}

/// translationTask는 화면에 있는 SwiftUI 뷰에서만 돌아서 잠깐 창을 만든다.
/// 모델이 있으면 화면 밖의 빈 창, 없으면 내려받기 창이 붙을 보이는 창. 끝나면 바로 닫아 메모리에 남기지 않는다.
@available(macOS 15.0, *)
@MainActor
private final class TranslationHost: NSObject, NSWindowDelegate {
    private static var current: TranslationHost?
    private var window: NSWindow?
    private var finish: ((Result<String, Error>) -> Void)?

    static func run(_ text: String, from: Locale.Language, to: Locale.Language, needsDownload: Bool) async throws -> String {
        current?.complete(.failure(CancellationError()))
        let host = TranslationHost()
        current = host
        return try await withCheckedThrowingContinuation { continuation in
            host.finish = { continuation.resume(with: $0) }
            host.open(text, from: from, to: to, visible: needsDownload)
        }
    }

    private func open(_ text: String, from: Locale.Language, to: Locale.Language, visible: Bool) {
        let view = TranslationTaskView(configuration: .init(source: from, target: to), text: text) { [weak self] result in
            self?.complete(result)
        }
        let window: NSWindow
        if visible {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L("번역 언어 내려받기", "Download Translation Languages")
            window.center()
        } else {
            window = NSPanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        }
        window.isReleasedWhenClosed = false
        window.level = .floating // 번역 결과 창에 가리지 않게
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        self.window = window
        if visible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        complete(.failure(TranslationFailure.cancelled))
    }

    private func complete(_ result: Result<String, Error>) {
        guard let finish else { return }
        self.finish = nil
        finish(result)
        window?.delegate = nil
        window?.close()
        window = nil
        if Self.current === self { Self.current = nil }
    }
}

@available(macOS 15.0, *)
private struct TranslationTaskView: View {
    let configuration: TranslationSession.Configuration
    let text: String
    let done: @MainActor (Result<String, Error>) -> Void

    var body: some View {
        Text(L("언어를 받은 뒤 번역을 이어 갑니다. 번역할 글은 기기 밖으로 나가지 않습니다.",
               "Translation continues once the languages are downloaded. Your text stays on this Mac."))
            .font(.callout)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    let blocks = TranslationText.blocks(text)
                    let requests = blocks.enumerated().filter { !$0.element.body.isEmpty }
                        .map { TranslationSession.Request(sourceText: $0.element.body, clientIdentifier: String($0.offset)) }
                    var translated: [Int: String] = [:]
                    for response in try await session.translations(from: requests) {
                        if let index = response.clientIdentifier.flatMap(Int.init) { translated[index] = response.targetText }
                    }
                    await done(.success(TranslationText.rebuild(blocks, translated: translated)))
                } catch {
                    await done(.failure(error))
                }
            }
    }
}

extension OCRRunner {
    /// 영역 글을 문단으로 이어 읽은 뒤 번역 — 줄마다 끊긴 채로 옮기면 문장이 깨진다
    public static func recognizeAndTranslate(_ image: CGImage) async {
        do {
            let text = try await TextRecognizer.recognize(image, lineMode: .paragraphs).precomposedStringWithCanonicalMapping
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Toast.show(L("글자를 찾지 못했습니다", "No text found"))
                return
            }
            await translate(text)
        } catch {
            Toast.show(L("텍스트 추출 실패: \(error.localizedDescription)", "Text recognition failed: \(error.localizedDescription)"))
        }
    }

    /// 번역해서 결과 창에 보여 준다. 클립보드는 창에서 복사를 누를 때만 바뀐다.
    public static func translate(_ text: String) async {
        let logger = Logger(subsystem: "dev.polymac", category: "translate")
        let panel = TranslationResultPanel.show(original: text)
        let start = Date()
        do {
            let result = try await TextTranslator.translate(text)
            let seconds = Date().timeIntervalSince(start)
            // 글 내용은 로그에 남기지 않는다
            logger.notice("translated \(result.source, privacy: .public)->\(result.target, privacy: .public) chars=\(text.count) seconds=\(seconds, format: .fixed(precision: 2), privacy: .public)")
            panel.show(translation: result.text, source: result.source, target: result.target)
        } catch is CancellationError {
            logger.notice("translation cancelled")
            panel.dismiss()
        } catch TranslationFailure.cancelled {
            logger.notice("translation cancelled")
            panel.dismiss()
        } catch {
            logger.error("translation failed: \(error.localizedDescription, privacy: .public)")
            panel.dismiss()
            Toast.show(L("번역 실패: \(error.localizedDescription)", "Translation failed: \(error.localizedDescription)"))
        }
    }
}
