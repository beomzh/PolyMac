// 자원 예산 측정: OCR 지연과 메모리 (docs/ARCHITECTURE.md 3). scripts/ocr-bench.sh --budget
import Darwin
import AppKit
import OCRModule

/// Activity Monitor의 "메모리"와 같은 값 (phys_footprint)
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

func runBudget(folder: URL) async throws {
    let names = (try FileManager.default.contentsOfDirectory(atPath: folder.path)).filter { $0.hasSuffix(".png") }.sorted()
    let images = names.compactMap { NSImage(contentsOf: folder.appendingPathComponent($0))?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    guard let first = images.first else { print("샘플이 없습니다"); return }
    print(String(format: "before OCR: %.1f MB", footprintMB()))
    var start = Date()
    _ = try await TextRecognizer.recognize(first, lineMode: .keep)
    print(String(format: "first OCR (model load): %.0f ms, %.1f MB", Date().timeIntervalSince(start) * 1000, footprintMB()))
    var times: [Double] = []
    for _ in 0..<3 {
        for image in images {
            start = Date()
            _ = try await TextRecognizer.recognize(image, lineMode: .keep)
            times.append(Date().timeIntervalSince(start) * 1000)
        }
    }
    times.sort()
    let p95 = times[min(times.count - 1, times.count * 95 / 100)]
    print(String(format: "later OCR (%d runs): median %.0f ms, p95 %.0f ms, max %.0f ms, over 500 ms: %d",
                 times.count, times[times.count / 2], p95, times[times.count - 1], times.filter { $0 > 500 }.count))
    print(String(format: "after OCR: %.1f MB", footprintMB()))
    try await Task.sleep(for: .seconds(30))
    print(String(format: "30 s later: %.1f MB", footprintMB()))
}
