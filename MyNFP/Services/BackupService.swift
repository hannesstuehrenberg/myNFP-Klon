import Foundation
import Observation
import UIKit
import NFPCore

/// Automatische Backups in einen frei wählbaren Ordner (z. B. iCloud Drive).
///
/// Funktioniert ohne kostenpflichtigen Developer-Account: Der Ordner wird über die Dateien-App gewählt
/// und als Security-Scoped-Bookmark gemerkt. Backups werden standardmäßig mit AES-256 verschlüsselt.
@MainActor
@Observable
final class BackupService {
    private static let bookmarkKey = "backup-folder-bookmark"
    private static let enabledKey = "backup-auto-enabled"
    private static let lastBackupKey = "backup-last-date"
    private static let lastExportKey = "backup-last-export"
    private static let encryptKey = "backup-encrypt"
    private static let passwordKey = "backup-password"
    private static let keepCountKey = "backup-keep-count"

    private(set) var folderName: String?
    private(set) var lastBackupDate: Date?
    /// Letzter manueller Export (zählt für die Backup-Erinnerung)
    private(set) var lastExportDate: Date?
    private(set) var lastError: String?
    private(set) var isRunning = false

    var autoBackupEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: Self.enabledKey) }
    }
    var encryptBackups: Bool {
        didSet { UserDefaults.standard.set(encryptBackups, forKey: Self.encryptKey) }
    }
    var keepCount: Int {
        didSet { UserDefaults.standard.set(keepCount, forKey: Self.keepCountKey) }
    }

    private var pendingTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        autoBackupEnabled = d.bool(forKey: Self.enabledKey)
        encryptBackups = d.object(forKey: Self.encryptKey) as? Bool ?? true
        keepCount = d.object(forKey: Self.keepCountKey) as? Int ?? 30
        lastBackupDate = d.object(forKey: Self.lastBackupKey) as? Date
        lastExportDate = d.object(forKey: Self.lastExportKey) as? Date
        folderName = resolveFolder()?.lastPathComponent
    }

    var hasFolder: Bool { folderName != nil }
    var hasPassword: Bool { !(Keychain.string(for: Self.passwordKey) ?? "").isEmpty }

    /// Zeitpunkt der letzten Sicherung außerhalb der App (automatisch oder Export)
    var lastExternalBackup: Date? {
        [lastBackupDate, lastExportDate].compactMap { $0 }.max()
    }

    func setPassword(_ pw: String) {
        if pw.isEmpty { Keychain.delete(Self.passwordKey) } else { Keychain.set(pw, for: Self.passwordKey) }
    }

    var password: String? { Keychain.string(for: Self.passwordKey) }

    func noteExport() {
        lastExportDate = Date()
        UserDefaults.standard.set(lastExportDate, forKey: Self.lastExportKey)
    }

    // MARK: Ordner

    func setFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = "Ordner konnte nicht gemerkt werden: \(error.localizedDescription)"
        }
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderName = nil
        autoBackupEnabled = false
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    // MARK: Sichern

    /// Nach einer Datenänderung: gebündelt nach einigen Sekunden sichern.
    func scheduleAutoBackup(_ dataProvider: @escaping @MainActor () -> AppData) {
        guard autoBackupEnabled, hasFolder else { return }
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            try? await self.backupNow(data: dataProvider())
        }
    }

    /// Täglich mindestens einmal sichern (beim App-Start/Vordergrund).
    func dailyBackupIfNeeded(data: AppData) {
        guard autoBackupEnabled, hasFolder else { return }
        if let last = lastBackupDate, Calendar.current.isDateInToday(last) { return }
        Task { try? await backupNow(data: data) }
    }

    func backupNow(data: AppData) async throws {
        guard let folder = resolveFolder() else {
            lastError = "Kein Backup-Ordner gewählt oder Zugriff verloren. Bitte Ordner neu wählen."
            throw CocoaError(.fileNoSuchFile)
        }
        if encryptBackups && !hasPassword {
            lastError = "Für verschlüsselte Backups bitte zuerst ein Backup-Passwort festlegen."
            throw CocoaError(.userCancelled)
        }
        isRunning = true
        defer { isRunning = false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let payload = BackupPayload(data: data, appVersion: version, deviceName: UIDevice.current.name)
        let pw = encryptBackups ? password : nil
        let keep = keepCount
        do {
            let fileData = try BackupCodec.encode(payload, password: pw)
            try await Task.detached(priority: .utility) {
                try BackupService.write(fileData, to: folder, keep: keep)
            }.value
            lastBackupDate = Date()
            UserDefaults.standard.set(lastBackupDate, forKey: Self.lastBackupKey)
            lastError = nil
        } catch {
            lastError = "Backup fehlgeschlagen: \(error.localizedDescription)"
            throw error
        }
    }

    nonisolated private static func write(_ data: Data, to folder: URL, keep: Int) throws {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let daily = folder.appendingPathComponent("NFP-Backup-\(f.string(from: Date())).nfpbackup")
        let latest = folder.appendingPathComponent("NFP-Backup-aktuell.nfpbackup")

        var coordError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        for target in [daily, latest] {
            coordinator.coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let e = coordError { throw e }
            if let e = writeError { throw e }
        }

        // Alte Tages-Backups aufräumen
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let dailies = files.filter { $0.lastPathComponent.hasPrefix("NFP-Backup-20") && $0.pathExtension == "nfpbackup" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in dailies.dropFirst(max(1, keep)) {
            coordinator.coordinate(writingItemAt: old, options: .forDeleting, error: nil) { url in
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Liste der Backups im gewählten Ordner (für die Wiederherstellung)
    func listBackups() -> [URL] {
        guard let folder = resolveFolder() else { return [] }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "nfpbackup" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func readBackup(_ url: URL) throws -> Data {
        guard let folder = resolveFolder() else { throw CocoaError(.fileNoSuchFile) }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        var result: Data?
        var readError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do { result = try Data(contentsOf: u) } catch { readError = error }
        }
        if let e = coordError { throw e }
        if let e = readError { throw e }
        return result ?? Data()
    }
}
