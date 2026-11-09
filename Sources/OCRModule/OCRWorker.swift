import CoreGraphics
import Foundation
import os

/// 글자·표 인식을 잠깐 쓰고 끝나는 별도 프로세스에서 돌린다.
///
/// Vision은 인식 모델을 한 번 읽으면 프로세스가 끝날 때까지 놓지 않는다 (OCR 한 번에 약 +65 MB, 공개 API로 내릴 방법이 없음).
/// 앱 안에서 돌리면 메뉴바 앱이 그 메모리를 계속 들고 있으므로, 같은 실행 파일을 `--ocr-worker`로 띄워 거기서 인식하고
/// 일 없이 `idleSeconds`가 지나면 끝낸다 — 그때 모델 메모리가 시스템으로 돌아간다. 측정: docs/ARCHITECTURE.md 3.
///
/// 이미지는 파이프로 넘기고 디스크에 쓰지 않는다. 인식한 글은 로그에 남기지 않는다.
public final class OCRWorker: @unchecked Sendable {
    public static let argument = "--ocr-worker"
    /// 일이 없으면 이만큼 뒤에 끝난다. 이어서 여러 번 인식할 때 모델을 다시 읽지 않게 잠깐은 남겨 둔다.
    public static let idleSeconds: TimeInterval = 60
    /// 한 번 인식에 이보다 오래 걸리면 일꾼을 끝내고 실패로 돌린다
    static let timeoutSeconds: TimeInterval = 30

    /// 앱 번들에서 실행 중일 때만 일꾼을 쓴다. 테스트·측정 도구에서는 같은 프로세스에서 인식한다.
    public static let shared = OCRWorker(executable: Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.executableURL : nil)

    private let executable: URL?
    private let queue = DispatchQueue(label: "dev.polymac.ocr-worker.client")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private static let logger = Logger(subsystem: "dev.polymac", category: "ocr-worker")

    init(executable: URL?) {
        self.executable = executable
        signal(SIGPIPE, SIG_IGN) // 일꾼이 막 끝난 파이프에 쓰면 앱이 죽지 않고 오류로 받는다
    }

    // MARK: 앱 쪽

    /// 글자 인식 (TextRecognizer.recognize와 같은 결과)
    public func recognizeText(_ image: CGImage, lineMode: OCRLineMode = .current) async throws -> String {
        guard executable != nil else { return try await TextRecognizer.recognize(image, lineMode: lineMode) }
        do {
            let reply = try await send(Request(kind: .text, lineMode: lineMode.rawValue), image: image)
            return reply.text ?? ""
        } catch WorkerError.launchFailed {
            return try await TextRecognizer.recognize(image, lineMode: lineMode)
        }
    }

    /// 표 인식 (TableRecognizer.recognize와 같은 결과)
    public func recognizeTables(_ image: CGImage) async throws -> [TableGrid] {
        guard executable != nil else { return try await TableRecognizer.recognize(image) }
        do {
            let reply = try await send(Request(kind: .tables, lineMode: nil), image: image)
            return (reply.tables ?? []).map(TableGrid.init(rows:))
        } catch WorkerError.launchFailed {
            return try await TableRecognizer.recognize(image)
        }
    }

    private func send(_ request: Request, image: CGImage) async throws -> Reply {
        guard let pixels = Pixels(image) else { throw WorkerError.message("could not read the image") }
        var header = request
        header.width = pixels.width; header.height = pixels.height; header.bytesPerRow = pixels.bytesPerRow
        let body = try JSONEncoder().encode(header)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.exchange(body, pixels.data) })
            }
        }
    }

    /// 요청 하나를 보내고 답을 받는다 (queue 위에서만). 일꾼이 쉬다가 끝났으면 새로 띄워 한 번 더 해 본다.
    private func exchange(_ header: Data, _ pixels: Data) throws -> Reply {
        let start = Date()
        for attempt in 1...2 {
            do {
                let (input, output) = try running()
                try Frame.write(header, to: input)
                try Frame.write(pixels, to: input)
                guard let data = try Frame.read(from: output, timeout: Self.timeoutSeconds) else { throw WorkerError.closed }
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                if let message = reply.error { throw WorkerError.message(message) }
                Self.logger.info("ocr worker reply in \(Int(Date().timeIntervalSince(start) * 1000)) ms (attempt \(attempt))")
                return reply
            } catch WorkerError.message(let message) {
                throw WorkerError.message(message)
            } catch WorkerError.launchFailed {
                // 일꾼을 띄울 수 없으면 앱 안에서 인식한다 (부르는 쪽). 일꾼이 인식 중에 죽은 경우는 여기로 오지 않는다 —
                // 같은 이미지를 앱 안에서 다시 읽다가 앱까지 죽지 않게.
                Self.logger.error("ocr worker could not start — recognizing in-process")
                throw WorkerError.launchFailed
            } catch WorkerError.timedOut {
                // 같은 이미지를 다시 맡기면 또 오래 걸린다 — 일꾼만 끝내고 바로 실패로 돌린다
                Self.logger.error("ocr worker timed out after \(Int(Self.timeoutSeconds)) s")
                stop()
                throw WorkerError.timedOut
            } catch {
                Self.logger.notice("ocr worker attempt \(attempt) failed: \(String(describing: error), privacy: .public)")
                stop()
                if attempt == 2 { throw error }
            }
        }
        throw WorkerError.closed
    }

    private func running() throws -> (FileHandle, FileHandle) {
        if let process, process.isRunning, let input, let output { return (input, output) }
        stop()
        guard let executable else { throw WorkerError.closed }
        let process = Process()
        process.executableURL = executable
        process.arguments = [Self.argument]
        let toWorker = Pipe(), fromWorker = Pipe()
        process.standardInput = toWorker
        process.standardOutput = fromWorker
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw WorkerError.launchFailed }
        Self.logger.info("ocr worker started pid=\(process.processIdentifier)")
        self.process = process
        input = toWorker.fileHandleForWriting
        output = fromWorker.fileHandleForReading
        return (toWorker.fileHandleForWriting, fromWorker.fileHandleForReading)
    }

    /// 지금 떠 있는 일꾼 (테스트에서 확인용)
    var workerPID: Int32? { queue.sync { process?.isRunning == true ? process?.processIdentifier : nil } }

    /// 일꾼을 끝낸다. 다음 요청 때 새로 띄운다.
    func shutDown() { queue.sync { stop() } }

    private func stop() {
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil
    }

    // MARK: 일꾼 쪽

    /// `--ocr-worker`로 실행됐을 때 main에서 부른다. 표준 입력이 닫히거나 쉬는 시간이 지나면 프로세스를 끝낸다.
    public static func serve() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let logger = Logger(subsystem: "dev.polymac", category: "ocr-worker")
        let input = FileHandle.standardInput, output = FileHandle.standardOutput
        let lastUse = OSAllocatedUnfairLock(initialState: Date())
        let busy = OSAllocatedUnfairLock(initialState: false)
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: 5)
                let idle = busy.withLock { $0 } ? 0 : Date().timeIntervalSince(lastUse.withLock { $0 })
                if idle >= idleSeconds {
                    logger.info("ocr worker exits after \(Int(idle)) s idle")
                    exit(0)
                }
            }
        }
        logger.info("ocr worker ready")
        while true {
            guard let header = try? Frame.read(from: input, timeout: nil),
                  let pixels = try? Frame.read(from: input, timeout: nil)
            else {
                logger.info("ocr worker input closed")
                exit(0)
            }
            busy.withLock { $0 = true }
            let reply = handle(header, pixels)
            lastUse.withLock { $0 = Date() }
            busy.withLock { $0 = false }
            guard let data = try? JSONEncoder().encode(reply), (try? Frame.write(data, to: output)) != nil else { exit(0) }
        }
    }

    private static func handle(_ header: Data, _ pixels: Data) -> Reply {
        do {
            let request = try JSONDecoder().decode(Request.self, from: header)
            guard let image = Pixels(width: request.width, height: request.height, bytesPerRow: request.bytesPerRow, data: pixels).image
            else { return Reply(error: "bad image") }
            let result = blocking { () async throws -> Reply in
                switch request.kind {
                case .text:
                    let mode = request.lineMode.flatMap(OCRLineMode.init(rawValue:)) ?? .current
                    return Reply(text: try await TextRecognizer.recognize(image, lineMode: mode))
                case .tables:
                    return Reply(tables: try await TableRecognizer.recognize(image).map(\.rows))
                }
            }
            return try result.get()
        } catch {
            return Reply(error: error.localizedDescription)
        }
    }

    /// 일꾼은 한 번에 하나씩 처리하므로 비동기 인식을 그 자리에서 기다린다
    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<Result<T, Error>?>(initialState: nil)
        Task.detached {
            let result = await Result { try await work() }
            box.withLock { $0 = result }
            semaphore.signal()
        }
        semaphore.wait()
        return box.withLock { $0 }!
    }

    // MARK: 주고받는 형식

    enum Kind: String, Codable { case text, tables }

    struct Request: Codable {
        var kind: Kind
        var lineMode: String?
        var width = 0, height = 0, bytesPerRow = 0
    }

    struct Reply: Codable {
        var text: String?
        var tables: [[[String]]]?
        var error: String?
    }

    enum WorkerError: Error, CustomStringConvertible {
        case closed, timedOut, launchFailed
        case message(String)
        var description: String {
            switch self {
            case .closed: "worker closed"
            case .launchFailed: "worker could not start"
            case .timedOut: "worker timed out"
            case .message(let message): message
            }
        }
    }
}

extension OCRWorker.WorkerError: LocalizedError {
    var errorDescription: String? { description }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

/// 길이(4바이트, big-endian) + 내용. 파이프 한 쪽에서 쓰고 다른 쪽에서 읽는다.
enum Frame {
    static let maxLength = 512 * 1024 * 1024

    static func write(_ data: Data, to handle: FileHandle) throws {
        var length = UInt32(data.count).bigEndian
        try writeAll(Data(bytes: &length, count: 4), handle.fileDescriptor)
        try writeAll(data, handle.fileDescriptor)
    }

    /// 상대가 닫았으면 nil. `timeout`이 있으면 그 안에 첫 바이트가 와야 한다.
    static func read(from handle: FileHandle, timeout: TimeInterval?) throws -> Data? {
        let fd = handle.fileDescriptor
        if let timeout {
            var poll = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            var ready: Int32
            repeat { ready = Darwin.poll(&poll, 1, Int32(timeout * 1000)) } while ready < 0 && errno == EINTR
            if ready == 0 { throw OCRWorker.WorkerError.timedOut }
        }
        guard let head = try readExactly(4, fd) else { return nil }
        let length = Int(head.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) })
        guard length <= maxLength else { throw OCRWorker.WorkerError.message("frame too large") }
        guard let body = try readExactly(length, fd) else { throw OCRWorker.WorkerError.closed }
        return body
    }

    private static func writeAll(_ data: Data, _ fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw OCRWorker.WorkerError.closed
                }
                offset += written
            }
        }
    }

    private static func readExactly(_ count: Int, _ fd: Int32) throws -> Data? {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let n = Darwin.read(fd, buffer.baseAddress! + offset, count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw OCRWorker.WorkerError.closed
                }
                if n == 0 { break }
                offset += n
            }
        }
        if offset == 0 && count > 0 { return nil }
        guard offset == count else { throw OCRWorker.WorkerError.closed }
        return data
    }
}

/// RGBA 8비트(premultipliedLast) 픽셀. PNG로 묶는 것보다 빠르다 (큰 캡처에서 수백 ms 차이).
struct Pixels {
    let width: Int, height: Int, bytesPerRow: Int
    let data: Data

    init?(_ image: CGImage) {
        width = image.width; height = image.height; bytesPerRow = width * 4
        guard width > 0, height > 0 else { return nil }
        var data = Data(count: bytesPerRow * height)
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard ok else { return nil }
        self.data = data
    }

    init(width: Int, height: Int, bytesPerRow: Int, data: Data) {
        self.width = width; self.height = height; self.bytesPerRow = bytesPerRow; self.data = data
    }

    var image: CGImage? {
        guard width > 0, height > 0, bytesPerRow >= width * 4, data.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
