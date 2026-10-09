import Foundation
import CryptoKit
import CommonCrypto

/// Passwortbasierte Verschlüsselung für Backup-Dateien.
///
/// Format: `MYNFPENC1` (9 Bytes) · Salt (16) · Iterationen (UInt32, big endian) · AES-256-GCM (Nonce · Chiffrat · Tag)
/// Schlüsselableitung: PBKDF2-HMAC-SHA256.
public enum BackupCrypto {
    public static let magic = Data("MYNFPENC1".utf8)
    public static let defaultIterations: UInt32 = 310_000

    public enum CryptoError: LocalizedError {
        case wrongPassword
        case invalidFormat
        case keyDerivationFailed

        public var errorDescription: String? {
            switch self {
            case .wrongPassword: return "Falsches Passwort oder beschädigte Datei."
            case .invalidFormat: return "Die Datei ist kein gültiges verschlüsseltes Backup."
            case .keyDerivationFailed: return "Schlüsselableitung fehlgeschlagen."
            }
        }
    }

    public static func isEncrypted(_ data: Data) -> Bool {
        data.count > magic.count && data.prefix(magic.count) == magic
    }

    public static func encrypt(_ plain: Data, password: String, iterations: UInt32 = defaultIterations) throws -> Data {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytesCompat(16, $0.baseAddress!) }
        guard status else { throw CryptoError.keyDerivationFailed }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw CryptoError.invalidFormat }
        var out = Data()
        out.append(magic)
        out.append(salt)
        var it = iterations.bigEndian
        out.append(Data(bytes: &it, count: 4))
        out.append(combined)
        return out
    }

    public static func decrypt(_ data: Data, password: String) throws -> Data {
        guard isEncrypted(data), data.count > magic.count + 20 + 28 else { throw CryptoError.invalidFormat }
        var offset = magic.count
        let salt = data.subdata(in: offset..<(offset + 16)); offset += 16
        let itData = data.subdata(in: offset..<(offset + 4)); offset += 4
        let iterations = itData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
        guard iterations >= 1000, iterations <= 10_000_000 else { throw CryptoError.invalidFormat }
        let combined = data.subdata(in: offset..<data.count)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.wrongPassword
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let pw = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let result = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                 pw.map { Int8(bitPattern: $0) }, pw.count,
                                 saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                 &derived, derived.count)
        }
        guard result == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    /// SHA-256 als Hex-String
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Kryptographisch sichere Zufallsbytes (ohne Security-Framework-Abhängigkeit im Aufrufer).
func SecRandomCopyBytesCompat(_ count: Int, _ ptr: UnsafeMutableRawPointer) -> Bool {
    CCRandomGenerateBytes(ptr, count) == kCCSuccess
}
