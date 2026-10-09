import Foundation

/// Inhalt einer Backup-Datei (`.nfpbackup`), optional passwortverschlüsselt.
public struct BackupPayload: Codable, Sendable {
    public static let formatID = "mynfp-klon-backup"

    public var format: String
    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String?
    public var deviceName: String?
    public var data: AppData

    public init(data: AppData, appVersion: String? = nil, deviceName: String? = nil, createdAt: Date = Date()) {
        self.format = BackupPayload.formatID
        self.formatVersion = 1
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.data = data
    }
}

public enum BackupCodec {
    public enum BackupError: LocalizedError {
        case notABackup
        case passwordRequired
        public var errorDescription: String? {
            switch self {
            case .notABackup: return "Die Datei enthält kein gültiges Backup."
            case .passwordRequired: return "Dieses Backup ist verschlüsselt. Bitte Passwort eingeben."
            }
        }
    }

    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(isoFractional().string(from: date))
        }
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = isoFractional().date(from: s) ?? ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Ungültiges Datum: \(s)")
        }
        return d
    }

    private static func isoFractional() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    /// Erzeugt die Backup-Datei. Mit Passwort wird sie AES-256-GCM-verschlüsselt.
    public static func encode(_ payload: BackupPayload, password: String?) throws -> Data {
        let json = try encoder(pretty: password == nil).encode(payload)
        if let password, !password.isEmpty {
            return try BackupCrypto.encrypt(json, password: password)
        }
        return json
    }

    /// Liest eine Backup-Datei (JSON, verschlüsselt oder Export-ZIP).
    public static func decode(_ fileData: Data, password: String?) throws -> BackupPayload {
        var data = fileData
        if ZipReader.isZip(data) {
            let entries = try ZipReader.entries(data)
            guard let json = entries.first(where: { $0.key.hasSuffix(".json") && $0.key.contains("Daten") })?.value
                    ?? entries.first(where: { $0.key.hasSuffix(".nfpbackup") })?.value else {
                throw BackupError.notABackup
            }
            data = json
        }
        if BackupCrypto.isEncrypted(data) {
            guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
            data = try BackupCrypto.decrypt(data, password: password)
        }
        let dec = decoder()
        if let payload = try? dec.decode(BackupPayload.self, from: data), payload.format == BackupPayload.formatID {
            return payload
        }
        // Auch die reine Datenbank-Datei akzeptieren
        if let app = try? dec.decode(AppData.self, from: data), !app.days.isEmpty || !app.cycleMeta.isEmpty {
            return BackupPayload(data: app)
        }
        throw BackupError.notABackup
    }

    public static func needsPassword(_ fileData: Data) -> Bool {
        if ZipReader.isZip(fileData), let entries = try? ZipReader.entries(fileData) {
            return entries.values.contains(where: BackupCrypto.isEncrypted)
        }
        return BackupCrypto.isEncrypted(fileData)
    }
}

// MARK: - Zusammenführen beim Import

public enum ImportMode: String, CaseIterable, Identifiable, Sendable {
    /// Alle vorhandenen Daten werden durch das Backup ersetzt
    case replace
    /// Tage aus dem Backup ergänzen, vorhandene Tage bleiben erhalten
    case mergeKeepExisting
    /// Tage aus dem Backup ergänzen und vorhandene überschreiben
    case mergeOverwrite

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .replace: return "Alle Daten ersetzen"
        case .mergeKeepExisting: return "Zusammenführen (vorhandene behalten)"
        case .mergeOverwrite: return "Zusammenführen (Backup überschreibt)"
        }
    }
}

public enum DataMerger {
    public static func merge(current: AppData, imported: AppData, mode: ImportMode) -> AppData {
        switch mode {
        case .replace:
            var d = imported
            d.modifiedAt = Date()
            return d
        case .mergeKeepExisting, .mergeOverwrite:
            var d = current
            let overwrite = mode == .mergeOverwrite
            for (date, entry) in imported.days where overwrite || d.days[date] == nil {
                d.days[date] = entry
            }
            // Kataloge per ID ergänzen
            for cat in imported.catalogs where !d.catalogs.contains(where: { $0.id == cat.id }) {
                d.catalogs.append(cat)
            }
            for (start, meta) in imported.cycleMeta where overwrite || d.cycleMeta[start] == nil {
                d.cycleMeta[start] = meta
            }
            // Unbekannte Zusatzleisten ergänzen
            for bar in imported.settings.bars where !d.settings.bars.contains(where: { $0.id == bar.id }) {
                d.settings.bars.append(bar)
            }
            d.modifiedAt = Date()
            return d
        }
    }
}
