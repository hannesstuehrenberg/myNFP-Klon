import Foundation

/// Ausfallsichere lokale Speicherung.
///
/// - Jede Speicherung schreibt eine einzige Datei atomar (erst temporär, dann umbenannt).
/// - Die Datei beginnt mit einer SHA-256-Prüfsumme des Inhalts; beschädigte Dateien werden erkannt.
/// - Vor jedem Schreiben wird der letzte gültige Stand als `previous` aufbewahrt.
/// - Täglich wird ein Snapshot angelegt (7 tägliche + 12 monatliche werden aufbewahrt).
/// - Beim Laden wird bei Beschädigung automatisch auf den letzten gültigen Stand zurückgegriffen.
/// - Unter iOS werden die Dateien mit Data Protection „Complete“ verschlüsselt.
public final class DataStore: @unchecked Sendable {
    public struct LoadResult {
        public var data: AppData
        /// Gesetzt, wenn die Hauptdatei unlesbar war und aus einer Sicherung wiederhergestellt wurde
        public var recoveredFrom: String?
        public var problems: [String]
        public var isFirstLaunch: Bool
    }

    public struct SnapshotInfo: Identifiable, Hashable {
        public var id: URL { url }
        public var url: URL
        public var date: Date
        public var size: Int
        /// Sicherheits-Snapshot vor Import/Wiederherstellung (statt täglichem Snapshot)
        public var isSafety: Bool
    }

    public enum StoreError: LocalizedError {
        case checksumMismatch
        case invalidFile
        case verificationFailed

        public var errorDescription: String? {
            switch self {
            case .checksumMismatch: return "Prüfsumme stimmt nicht – Datei beschädigt."
            case .invalidFile: return "Ungültige Datei."
            case .verificationFailed: return "Die gespeicherten Daten konnten nicht verifiziert werden."
            }
        }
    }

    public let directory: URL
    private let fm = FileManager.default
    private let ext = "nfpstore"

    public var mainURL: URL { directory.appendingPathComponent("data.\(ext)") }
    public var previousURL: URL { directory.appendingPathComponent("data.previous.\(ext)") }
    public var snapshotsDirectory: URL { directory.appendingPathComponent("Snapshots", isDirectory: true) }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NFPData", isDirectory: true)
    }

    public init(directory: URL = DataStore.defaultDirectory) {
        self.directory = directory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
    }

    // MARK: Kodierung

    static func encodeFile(_ data: AppData) throws -> Data {
        let json = try BackupCodec.encoder().encode(data)
        var out = Data((BackupCrypto.sha256Hex(json) + "\n").utf8)
        out.append(json)
        return out
    }

    static func decodeFile(_ file: Data) throws -> AppData {
        guard file.count > 65, let nl = file.firstIndex(of: 0x0A), nl - file.startIndex == 64 else {
            throw StoreError.invalidFile
        }
        let checksum = String(decoding: file[file.startIndex..<nl], as: UTF8.self)
        let json = file[(nl + 1)...]
        guard BackupCrypto.sha256Hex(Data(json)) == checksum else { throw StoreError.checksumMismatch }
        return try BackupCodec.decoder().decode(AppData.self, from: Data(json))
    }

    // MARK: Laden

    public func load() -> LoadResult {
        var problems: [String] = []
        let mainExists = fm.fileExists(atPath: mainURL.path)
        if mainExists {
            do {
                let d = try DataStore.decodeFile(Data(contentsOf: mainURL))
                return LoadResult(data: d, recoveredFrom: nil, problems: [], isFirstLaunch: false)
            } catch {
                problems.append("Hauptdatei: \(error.localizedDescription)")
            }
        }
        // Fallbacks: vorheriger Stand, dann Snapshots (neueste zuerst)
        var candidates: [(String, URL)] = [("letzter Speicherstand", previousURL)]
        candidates += listSnapshots().map { ("Snapshot vom \(Self.displayFormatter.string(from: $0.date))", $0.url) }
        for (label, url) in candidates where fm.fileExists(atPath: url.path) {
            do {
                let d = try DataStore.decodeFile(Data(contentsOf: url))
                if mainExists {
                    // Beschädigte Datei für eine spätere Analyse aufheben und reparieren
                    let broken = directory.appendingPathComponent("data.broken-\(Int(Date().timeIntervalSince1970)).\(ext)")
                    try? fm.moveItem(at: mainURL, to: broken)
                }
                try? save(d, keepPrevious: false)
                return LoadResult(data: d, recoveredFrom: label, problems: problems, isFirstLaunch: false)
            } catch {
                problems.append("\(label): \(error.localizedDescription)")
            }
        }
        return LoadResult(data: AppData(), recoveredFrom: nil, problems: problems,
                          isFirstLaunch: !mainExists && problems.isEmpty)
    }

    // MARK: Speichern

    public func save(_ data: AppData, keepPrevious: Bool = true) throws {
        let file = try DataStore.encodeFile(data)
        // Verifikation vor dem Schreiben
        _ = try DataStore.decodeFile(file)
        if keepPrevious, fm.fileExists(atPath: mainURL.path),
           let current = try? Data(contentsOf: mainURL), (try? DataStore.decodeFile(current)) != nil {
            try write(current, to: previousURL)
        }
        try write(file, to: mainURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    // MARK: Snapshots

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    /// Legt höchstens einen Snapshot pro Tag an und räumt alte auf.
    @discardableResult
    public func snapshotIfNeeded(_ data: AppData, now: Date = Date()) -> Bool {
        let name = "snapshot-\(Self.dayFormatter.string(from: now)).\(ext)"
        let url = snapshotsDirectory.appendingPathComponent(name)
        guard !fm.fileExists(atPath: url.path), !data.days.isEmpty else { return false }
        do {
            try write(try DataStore.encodeFile(data), to: url)
            pruneSnapshots()
            return true
        } catch {
            return false
        }
    }

    static let safetyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    public func listSnapshots() -> [SnapshotInfo] {
        let files = (try? fm.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { url -> SnapshotInfo? in
            let name = url.deletingPathExtension().lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if name.hasPrefix("snapshot-"), let date = Self.dayFormatter.date(from: String(name.dropFirst(9))) {
                return SnapshotInfo(url: url, date: date, size: size, isSafety: false)
            }
            if name.hasPrefix("safety-"), let date = Self.safetyFormatter.date(from: String(name.dropFirst(7))) {
                return SnapshotInfo(url: url, date: date, size: size, isSafety: true)
            }
            return nil
        }.sorted { $0.date > $1.date }
    }

    /// Sicherheits-Snapshot vor riskanten Aktionen (Import, Wiederherstellung, Löschen). Die letzten 5 bleiben erhalten.
    @discardableResult
    public func safetySnapshot(_ data: AppData, now: Date = Date()) -> Bool {
        guard !data.days.isEmpty else { return false }
        let url = snapshotsDirectory.appendingPathComponent("safety-\(Self.safetyFormatter.string(from: now)).\(ext)")
        do {
            try write(try DataStore.encodeFile(data), to: url)
        } catch {
            return false
        }
        let safety = listSnapshots().filter(\.isSafety)
        for s in safety.dropFirst(5) { try? fm.removeItem(at: s.url) }
        return true
    }

    public func loadSnapshot(_ info: SnapshotInfo) throws -> AppData {
        try DataStore.decodeFile(Data(contentsOf: info.url))
    }

    /// Behält die 7 neuesten Tages-Snapshots und darüber hinaus je einen pro Monat für 12 Monate.
    func pruneSnapshots() {
        let all = listSnapshots().filter { !$0.isSafety }
        var keep = Set(all.prefix(7).map(\.url))
        var months = Set<String>()
        let cal = Calendar(identifier: .gregorian)
        for s in all.dropFirst(7) {
            let c = cal.dateComponents([.year, .month], from: s.date)
            let key = "\(c.year!)-\(c.month!)"
            if !months.contains(key) && months.count < 12 {
                months.insert(key)
                keep.insert(s.url)
            }
        }
        for s in all where !keep.contains(s.url) {
            try? fm.removeItem(at: s.url)
        }
    }

    /// Löscht alle lokalen Daten (inkl. Snapshots).
    public func wipe() throws {
        for url in [mainURL, previousURL] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        for s in listSnapshots() where !s.isSafety { try? fm.removeItem(at: s.url) }
    }
}
