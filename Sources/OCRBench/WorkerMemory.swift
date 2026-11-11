// OCR 일꾼을 쓸 때 부르는 쪽(앱) 메모리가 늘지 않는지 (docs/ARCHITECTURE.md 3, scripts/resource-budget.sh).
// Vision 모델은 인식한 프로세스에 남으므로, 앱이 일꾼에게 맡기면 앱 메모리는 거의 그대로여야 한다.
// 이 도구는 다른 테스트와 섞이지 않는 별도 프로세스라 그 차이를 그대로 잰다.
import AppKit
import OCRModule

/// 결과는 `key=value` 줄로 내보낸다 (스크립트가 읽는다)
func runWorkerMemory(worker: URL, sample: URL, rounds: Int) async throws {
    guard let image = NSImage(contentsOf: sample)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("샘플을 읽지 못했습니다: \(sample.path)"); exit(1)
    }
    let client = OCRWorker(executable: worker)
    let before = footprintMB()
    var chars = 0
    for _ in 0..<rounds { chars = try await client.recognizeText(image, lineMode: .keep).count }
    let after = footprintMB()
    print(String(format: "caller_before_mb=%.1f", before))
    print(String(format: "caller_after_mb=%.1f", after))
    print(String(format: "caller_growth_mb=%.1f", after - before))
    print("recognized_chars=\(chars)")
}
