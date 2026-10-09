import Foundation
import LocalAuthentication
import CryptoKit
import Observation

/// Code-Sperre mit optionaler Face ID / Touch ID.
/// Der Code wird nur als gesalzener SHA-256-Hash in der Keychain gespeichert.
@MainActor
@Observable
final class AppLock {
    private static let pinKey = "app-lock-pin"
    private static let biometricsKey = "app-lock-biometrics"
    private static let delayKey = "app-lock-delay"

    private(set) var isLocked: Bool
    private(set) var isEnabled: Bool
    var biometricsEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricsEnabled, forKey: Self.biometricsKey) }
    }
    /// Sperren nach X Sekunden im Hintergrund (0 = sofort)
    var lockDelaySeconds: Int {
        didSet { UserDefaults.standard.set(lockDelaySeconds, forKey: Self.delayKey) }
    }

    private(set) var failedAttempts = 0
    private(set) var lockedOutUntil: Date?
    private var backgroundedAt: Date?

    init() {
        let enabled = Keychain.data(for: Self.pinKey) != nil
        isEnabled = enabled
        isLocked = enabled
        biometricsEnabled = UserDefaults.standard.bool(forKey: Self.biometricsKey)
        lockDelaySeconds = UserDefaults.standard.integer(forKey: Self.delayKey)
    }

    // MARK: Code verwalten

    func setPIN(_ pin: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        var stored = salt
        stored.append(Self.hash(pin, salt: salt))
        Keychain.set(stored, for: Self.pinKey)
        isEnabled = true
        isLocked = false
    }

    func removePIN() {
        Keychain.delete(Self.pinKey)
        isEnabled = false
        isLocked = false
        biometricsEnabled = false
    }

    func verify(_ pin: String) -> Bool {
        guard let stored = Keychain.data(for: Self.pinKey), stored.count == 48 else { return false }
        let salt = stored.prefix(16)
        let hash = stored.suffix(32)
        return Self.hash(pin, salt: Data(salt)) == Data(hash)
    }

    private static func hash(_ pin: String, salt: Data) -> Data {
        var d = salt
        d.append(Data(pin.utf8))
        return Data(SHA256.hash(data: d))
    }

    // MARK: Entsperren

    var isLockedOut: Bool {
        if let until = lockedOutUntil, until > Date() { return true }
        return false
    }

    @discardableResult
    func unlock(with pin: String) -> Bool {
        guard !isLockedOut else { return false }
        if verify(pin) {
            isLocked = false
            failedAttempts = 0
            lockedOutUntil = nil
            return true
        }
        failedAttempts += 1
        if failedAttempts >= 5 {
            // Zunehmende Wartezeit nach wiederholten Fehlversuchen
            let wait = min(300, 30 * (failedAttempts - 4))
            lockedOutUntil = Date().addingTimeInterval(TimeInterval(wait))
        }
        return false
    }

    var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometrie"
        }
    }

    var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func unlockWithBiometrics() async {
        guard isEnabled, biometricsEnabled, isLocked else { return }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Code eingeben"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                  localizedReason: "Entsperre deine Zyklusdaten")
            if ok {
                isLocked = false
                failedAttempts = 0
            }
        } catch {
            // Nutzerin gibt stattdessen den Code ein
        }
    }

    // MARK: Lebenszyklus

    func didEnterBackground() {
        backgroundedAt = Date()
        if isEnabled && lockDelaySeconds == 0 { isLocked = true }
    }

    func willEnterForeground() {
        guard isEnabled else { return }
        if let t = backgroundedAt, Date().timeIntervalSince(t) >= TimeInterval(lockDelaySeconds) {
            isLocked = true
        }
        backgroundedAt = nil
    }
}
