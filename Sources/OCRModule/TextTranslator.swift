import AppKit
import NaturalLanguage
import PolyMacCore
import SwiftUI
import Translation
import os

/// 어느 언어에서 어느 언어로 옮길지. 내 언어가 아닌 글은 내 언어로, 내 언어로 된 글은 영어로 (영어가 내 언어면 한국어로).
enum TranslationDirection {
    /// 글의 주 언어. 짧아서 판단이 안 되면 한글이 있으면 한국어, 아니면 영어로 본다.
    static func source(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        if let language = recognizer.dominantLanguage { return language.rawValue }
        return text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } ? "ko" : "en"
    }

    static func target(source: String, preferred: String) -> String {
        guard base(source) == base(preferred) else { return preferred }
        return base(preferred) == "en" ? "ko" : "en"
    }

    /// 시스템 첫 번째 언어 ("ko-KR" → "ko")
    static var preferred: String {
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
                    let response = try await session.translate(text)
                    await done(.success(response.targetText))
                } catch {
                    await done(.failure(error))
                }
            }
    }
}

extension OCRRunner {
    /// 영역 글을 문단으로 이어 읽은 뒤 번역 — 줄마다 끊긴 채로 옮기면 문장이 깨진다
    @discardableResult
    public static func recognizeTranslateAndCopy(_ image: CGImage) async -> Bool {
        do {
            let text = try await TextRecognizer.recognize(image, lineMode: .paragraphs).precomposedStringWithCanonicalMapping
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Toast.show(L("글자를 찾지 못했습니다", "No text found"))
                return false
            }
            return await translateAndCopy(text)
        } catch {
            Toast.show(L("텍스트 추출 실패: \(error.localizedDescription)", "Text recognition failed: \(error.localizedDescription)"))
            return false
        }
    }

    /// 번역 → 클립보드 → 미리보기. 원문은 단추로 다시 복사할 수 있다.
    @discardableResult
    public static func translateAndCopy(_ text: String) async -> Bool {
        let logger = Logger(subsystem: "dev.polymac", category: "translate")
        let start = Date()
        do {
            let result = try await TextTranslator.translate(text)
            let seconds = Date().timeIntervalSince(start)
            // 글 내용은 로그에 남기지 않는다
            logger.info("translated \(result.source, privacy: .public)->\(result.target, privacy: .public) chars=\(text.count) seconds=\(seconds, format: .fixed(precision: 2), privacy: .public)")
            PasteboardWriter.copy(result.text, origin: .ocr)
            let preview = result.text.count > 200 ? String(result.text.prefix(200)) + "…" : result.text
            Toast.show(L("번역을 클립보드에 복사했습니다", "Translation copied to the clipboard"), content: preview, duration: 4,
                       actions: [Toast.Action(L("원문 복사", "Copy Original")) { PasteboardWriter.copy(text, origin: .ocr) }])
            return true
        } catch is CancellationError {
            logger.notice("translation cancelled")
            return false
        } catch TranslationFailure.cancelled {
            logger.notice("translation cancelled")
            return false
        } catch {
            logger.error("translation failed: \(error.localizedDescription, privacy: .public)")
            Toast.show(L("번역 실패: \(error.localizedDescription)", "Translation failed: \(error.localizedDescription)"))
            return false
        }
    }
}
