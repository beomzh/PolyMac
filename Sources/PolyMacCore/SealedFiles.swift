import CryptoKit
import Foundation
import Security
import os

/// 앱 데이터 파일을 AES-GCM으로 봉인해 쓰고 읽는다 (docs/SECURITY.md 3).
/// 파일 = "PMS1" + nonce + 암호문 + 태그. 같은 사용자 권한으로 도는 다른 프로그램이 파일을 읽어도 내용을 알 수 없고,
/// 바뀐 파일은 열리지 않는다. 키는 디스크에 두지 않고 키체인에 둔다 (KeychainKey).
public struct SealedFiles: Sendable {
    static let magic = Data("PMS1".utf8)
    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public enum Failure: Error {
        /// 봉인은 됐는데 이 키로 열 수 없거나 내용이 바뀜
        case cannotOpen
    }

    public static func isSealed(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    public func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw Failure.cannotOpen }
        return Self.magic + combined
    }

    /// 봉인 안 된 예전 파일(평문)은 그대로 돌려준다 — 처음 켤 때 다시 봉인해 옮긴다
    public func open(_ data: Data) throws -> Data {
        guard Self.isSealed(data) else { return data }
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count)), using: key)
        } catch {
            throw Failure.cannotOpen
        }
    }

    /// 봉인해서 0600으로 쓴다
    public func write(_ data: Data, to url: URL) throws {
        try AppPaths.writePrivate(try seal(data), to: url)
    }

    public func read(_ url: URL) throws -> Data {
        try open(Data(contentsOf: url))
    }

    /// 평문 파일이면 봉인해 다시 쓴다. 바꿨으면 true
    @discardableResult
    public func sealInPlace(_ url: URL) throws -> Bool {
        let data = try Data(contentsOf: url)
        guard !Self.isSealed(data) else { return false }
        try write(data, to: url)
        return true
    }
}

/// 키체인(로그인 키체인)에 둔 256비트 키. 키체인 항목은 만든 앱(같은 서명)만 묻지 않고 읽을 수 있다.
public enum KeychainKey {
    private static let service = "dev.polymac"
    private static let logger = Logger(subsystem: "dev.polymac", category: "keychain")

    public enum Failure: Error, CustomStringConvertible {
        /// 키체인이 잠겼거나 사용자가 허용하지 않음 — 새 키를 만들면 예전 기록을 영영 못 여니 만들지 않는다
        case unavailable(OSStatus)

        public var description: String {
            switch self {
            case .unavailable(let status):
                return (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            }
        }
    }

    /// 있으면 읽고, 처음이면 만들어 넣는다
    public static func loadOrCreate(account: String, label: String) throws -> SymmetricKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            logger.error("keychain read failed: \(status)")
            throw Failure.unavailable(status)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = label
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else {
            logger.error("keychain add failed: \(added)")
            throw Failure.unavailable(added)
        }
        logger.notice("created keychain key \(account, privacy: .public)")
        return key
    }
}
