import Compression
import Foundation

/// Windows에서 한글 이름이 깨지지 않는 zip.
/// macOS 기본 압축(Finder·ditto·zip)은 이름을 UTF-8로 쓰면서도 "UTF-8 이름" 표시(일반 목적 플래그 11번)를 남기지 않아
/// Windows가 옛 코드페이지로 읽어 이름이 깨진다. 여기서는 이름을 NFC로 바꾸고 그 표시를 켠다.
/// 숨김 파일(.DS_Store 등)·리소스 포크(__MACOSX, ._*)는 넣지 않는다.
public enum WindowsZip {
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// 4 GB 이상(zip64)은 지원하지 않는다
    static let sizeLimit: UInt64 = 0xFFFF_FFFF

    /// sources를 destination 하나의 zip으로 묶는다. 폴더는 그 이름부터 안쪽까지 들어간다.
    /// 끝나면 넣은 파일 수를 돌려준다. 실패하면 만들던 zip을 지운다.
    @discardableResult
    public static func create(from sources: [URL], to destination: URL) throws -> Int {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: destination)
        else { throw Failure(message: "cannot create \(destination.path)") }
        do {
            var writer = Writer(handle: handle)
            for source in sources {
                try add(source, as: nfcName(source), writer: &writer)
            }
            try writer.finish()
            try handle.close()
            return writer.fileCount
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// 디스크 원본 이름(NFD일 수 있음)을 NFC로. URL.lastPathComponent는 원본 형태를 잃으므로 경로 문자열을 쓴다.
    static func nfcName(_ url: URL) -> String {
        (url.path as NSString).lastPathComponent.precomposedStringWithCanonicalMapping
    }

    private static func add(_ url: URL, as name: String, writer: inout Writer) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
        if values.isSymbolicLink == true { return } // 링크는 Windows에서 의미가 없다
        let date = values.contentModificationDate ?? Date()
        if values.isDirectory == true {
            try writer.addDirectory(name + "/", date: date)
            let children = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
            for child in children where !child.hasPrefix(".") && child != "__MACOSX" {
                try add(url.appendingPathComponent(child), as: name + "/" + child.precomposedStringWithCanonicalMapping, writer: &writer)
            }
        } else {
            try writer.addFile(url, name: name, date: date)
        }
    }

    /// 실제 zip 형식 쓰기 (deflate, 플래그 11번 = UTF-8 이름)
    struct Writer {
        let handle: FileHandle
        private var central = Data()
        private var entries = 0
        private(set) var fileCount = 0

        init(handle: FileHandle) { self.handle = handle }

        private var offset: UInt64 { (try? handle.offset()) ?? 0 }

        mutating func addDirectory(_ name: String, date: Date) throws {
            let start = offset
            try checkLimit(start)
            let nameData = Data(name.utf8)
            handle.write(localHeader(name: nameData, method: 0, crc: 0, compressed: 0, size: 0, date: date))
            appendCentral(name: nameData, method: 0, crc: 0, compressed: 0, size: 0, date: date, offset: start, directory: true)
        }

        mutating func addFile(_ url: URL, name: String, date: Date) throws {
            let start = offset
            try checkLimit(start)
            let nameData = Data(name.utf8)
            // 크기·CRC는 다 쓴 뒤에 알 수 있어 자리만 잡아 두고 나중에 고친다
            handle.write(localHeader(name: nameData, method: 8, crc: 0, compressed: 0, size: 0, date: date))
            let dataStart = offset
            guard let input = try? FileHandle(forReadingFrom: url) else {
                throw Failure(message: "cannot read \(url.path)")
            }
            defer { try? input.close() }
            var crc = CRC32()
            var size: UInt64 = 0
            let out = handle
            let filter = try OutputFilter(.compress, using: .zlib) { chunk in
                if let chunk { out.write(chunk) }
            }
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                crc.update(chunk)
                size += UInt64(chunk.count)
                try filter.write(chunk)
            }
            try filter.finalize()
            let end = offset
            let compressed = end - dataStart
            guard size <= WindowsZip.sizeLimit, compressed <= WindowsZip.sizeLimit else {
                throw Failure(message: "file too large for zip (4 GB): \(url.path)")
            }
            // 로컬 헤더의 CRC·크기 자리(14번째 바이트부터 12바이트)를 고친다
            try handle.seek(toOffset: start + 14)
            var patch = Data()
            patch.le32(crc.value); patch.le32(UInt32(compressed)); patch.le32(UInt32(size))
            handle.write(patch)
            try handle.seek(toOffset: end)
            appendCentral(name: nameData, method: 8, crc: crc.value, compressed: UInt32(compressed), size: UInt32(size),
                          date: date, offset: start, directory: false)
            fileCount += 1
        }

        mutating func finish() throws {
            let start = offset
            try checkLimit(start)
            handle.write(central)
            var end = Data()
            end.le32(0x0605_4B50)
            end.le16(0); end.le16(0)
            end.le16(UInt16(min(entries, 0xFFFF))); end.le16(UInt16(min(entries, 0xFFFF)))
            end.le32(UInt32(central.count)); end.le32(UInt32(start))
            end.le16(0)
            handle.write(end)
        }

        private func checkLimit(_ offset: UInt64) throws {
            guard offset < WindowsZip.sizeLimit, entries < 0xFFFF else {
                throw Failure(message: "zip would exceed 4 GB or 65535 entries")
            }
        }

        private func localHeader(name: Data, method: UInt16, crc: UInt32, compressed: UInt32, size: UInt32, date: Date) -> Data {
            var d = Data()
            d.le32(0x0403_4B50)
            d.le16(20)          // 필요한 버전 2.0
            d.le16(0x0800)      // 플래그 11: 이름은 UTF-8
            d.le16(method)
            let (time, day) = dosDateTime(date)
            d.le16(time); d.le16(day)
            d.le32(crc); d.le32(compressed); d.le32(size)
            d.le16(UInt16(name.count)); d.le16(0)
            d.append(name)
            return d
        }

        private mutating func appendCentral(name: Data, method: UInt16, crc: UInt32, compressed: UInt32, size: UInt32,
                                            date: Date, offset: UInt64, directory: Bool) {
            var d = Data()
            d.le32(0x0201_4B50)
            d.le16(20)          // 만든 버전 2.0, MS-DOS 속성
            d.le16(20)
            d.le16(0x0800)
            d.le16(method)
            let (time, day) = dosDateTime(date)
            d.le16(time); d.le16(day)
            d.le32(crc); d.le32(compressed); d.le32(size)
            d.le16(UInt16(name.count)); d.le16(0); d.le16(0)
            d.le16(0); d.le16(0)
            d.le32(directory ? 0x10 : 0) // 폴더 속성
            d.le32(UInt32(offset))
            d.append(name)
            central.append(d)
            entries += 1
        }

        private func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let year = max((c.year ?? 1980) - 1980, 0)
            let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
            let day = UInt16(year << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
            return (time, day)
        }
    }

    struct CRC32 {
        private static let table: [UInt32] = (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            return c
        }
        private var crc: UInt32 = 0xFFFF_FFFF
        var value: UInt32 { crc ^ 0xFFFF_FFFF }

        mutating func update(_ data: Data) {
            var c = crc
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                for byte in bytes { c = Self.table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
            }
            crc = c
        }
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
