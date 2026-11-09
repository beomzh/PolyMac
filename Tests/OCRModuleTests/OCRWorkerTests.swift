import AppKit
import Foundation
import Testing
@testable import OCRModule

@Test func frameRoundTripsThroughAPipe() throws {
    let pipe = Pipe()
    let payloads = [Data(), Data("한글 frame".utf8), Data(repeating: 7, count: 300_000)]
    let writer = Thread { for data in payloads { try? Frame.write(data, to: pipe.fileHandleForWriting) }; try? pipe.fileHandleForWriting.close() }
    writer.start()
    for data in payloads {
        #expect(try Frame.read(from: pipe.fileHandleForReading, timeout: 5) == data)
    }
    #expect(try Frame.read(from: pipe.fileHandleForReading, timeout: 5) == nil) // 닫힌 뒤에는 nil
}

@Test func frameReadTimesOutWhenNothingArrives() {
    let pipe = Pipe()
    #expect(throws: OCRWorker.WorkerError.self) { try Frame.read(from: pipe.fileHandleForReading, timeout: 0.1) }
}

@Test func pixelsRebuildTheSameSizedImage() throws {
    let image = try #require(sample("english"))
    let pixels = try #require(Pixels(image))
    let rebuilt = try #require(Pixels(width: pixels.width, height: pixels.height, bytesPerRow: pixels.bytesPerRow, data: pixels.data).image)
    #expect(rebuilt.width == image.width && rebuilt.height == image.height)
    #expect(Pixels(width: 10, height: 10, bytesPerRow: 40, data: Data(count: 39)).image == nil) // 모자란 데이터는 거절
}

/// 실제로 일꾼 프로세스를 띄워 같은 결과가 나오는지. `swift build`로 만든 실행 파일이 있어야 한다.
@Test(.enabled(if: workerBinary != nil))
func workerProcessMatchesInProcessRecognition() async throws {
    let image = try #require(sample("mixed-ko-en"))
    let worker = OCRWorker(executable: workerBinary)
    defer { worker.shutDown() }
    let local = try await TextRecognizer.recognize(image, lineMode: .keep)
    let remote = try await worker.recognizeText(image, lineMode: .keep)
    #expect(remote == local)
    #expect(!remote.isEmpty)
    let first = try #require(worker.workerPID)

    // 일꾼이 사라져도 다음 요청에서 새로 띄운다
    kill(first, SIGKILL)
    try await Task.sleep(for: .milliseconds(200))
    let again = try await worker.recognizeText(image, lineMode: .keep)
    #expect(again == local)
    #expect(worker.workerPID != nil && worker.workerPID != first)
}

@Test(.enabled(if: workerBinary != nil))
func workerProcessRecognizesTables() async throws {
    let url = repoRoot.appendingPathComponent("Tests/OCRSamples/tables/ko-grid.png")
    let image = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let worker = OCRWorker(executable: workerBinary)
    defer { worker.shutDown() }
    #expect(try await worker.recognizeTables(image) == (try await TableRecognizer.recognize(image)))
}

@Test func missingWorkerExecutableFallsBackToInProcess() async throws {
    let image = try #require(sample("english"))
    let worker = OCRWorker(executable: URL(fileURLWithPath: "/nonexistent/PolyMac"))
    #expect(try await worker.recognizeText(image, lineMode: .keep) == (try await TextRecognizer.recognize(image, lineMode: .keep)))
    #expect(worker.workerPID == nil)
}

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// POLYMAC_WORKER로 다른 실행 파일(예: 설치한 서명된 앱)을 일꾼으로 시험할 수 있다
private let workerBinary: URL? = {
    let path = ProcessInfo.processInfo.environment["POLYMAC_WORKER"]
    let url = path.map(URL.init(fileURLWithPath:)) ?? repoRoot.appendingPathComponent(".build/debug/PolyMac")
    return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
}()

private func sample(_ name: String) -> CGImage? {
    NSImage(contentsOf: repoRoot.appendingPathComponent("Tests/OCRSamples/\(name).png"))?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
}
