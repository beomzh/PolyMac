import CryptoKit
import Foundation
import Testing
@testable import PolyMacCore

/// 봉인 파일: 왕복, 디스크에 평문이 남지 않음, 예전 평문 파일 읽기·다시 봉인, 변조·다른 키는 열리지 않음
@Test func sealedFilesRoundTripAndMigrate() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("polymac-sealed-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SealedFiles(key: SymmetricKey(size: .bits256))
    let secret = Data("비밀번호 아님 secret-token-123".utf8)

    let url = dir.appendingPathComponent("clipboard.json")
    try store.write(secret, to: url)
    let onDisk = try Data(contentsOf: url)
    #expect(SealedFiles.isSealed(onDisk))
    #expect(onDisk.range(of: Data("secret-token".utf8)) == nil)
    #expect(try store.read(url) == secret)
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)

    // 예전 평문 파일: 그대로 읽히고, 다시 봉인하면 평문이 사라진다
    let legacy = dir.appendingPathComponent("old.txt")
    try secret.write(to: legacy)
    #expect(try store.read(legacy) == secret)
    #expect(try store.sealInPlace(legacy))
    #expect(SealedFiles.isSealed(try Data(contentsOf: legacy)))
    #expect(try !store.sealInPlace(legacy)) // 이미 봉인됐으면 그대로
    #expect(try store.read(legacy) == secret)

    // 다른 키, 한 바이트 바뀐 파일은 열리지 않는다
    let other = SealedFiles(key: SymmetricKey(size: .bits256))
    #expect(throws: SealedFiles.Failure.self) { try other.read(url) }
    var tampered = onDisk
    tampered[tampered.count - 1] ^= 0x01
    #expect(throws: SealedFiles.Failure.self) { try store.open(tampered) }
}
