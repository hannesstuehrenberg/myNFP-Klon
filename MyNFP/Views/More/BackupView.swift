import SwiftUI
import UniformTypeIdentifiers
import NFPCore

/// Datensicherung: automatische Backups (z. B. in iCloud Drive), lokale Snapshots, Export & Import.
struct BackupView: View {
    @Environment(AppModel.self) private var model
    @Environment(BackupService.self) private var backup

    /// Nur ein fileImporter pro Ansicht: SwiftUI beachtet bei mehreren nur einen.
    enum PickerPurpose { case folder, importFile }
    @State private var showPicker = false
    @State private var pickerPurpose: PickerPurpose = .folder
    @State private var passwordSheet = false
    @State private var exportPassword = ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var busy = false
    @State private var message: String?

    // Import / Wiederherstellung
    @State private var importData: Data?
    @State private var importPassword = ""
    @State private var askImportPassword = false
    @State private var decoded: BackupPayload?
    @State private var importError: String?

    @State private var snapshotToRestore: DataStore.SnapshotInfo?
    @State private var confirmWipe = false
    @State private var confirmWipe2 = false

    var body: some View {
        Form {
            statusSection
            autoBackupSection
            snapshotSection
            exportSection
            importSection
            Section {
                Button("Alle Daten auf diesem iPhone löschen", role: .destructive) { confirmWipe = true }
            } footer: {
                Text("Löscht alle Zyklusdaten und lokalen Snapshots. Backups in iCloud Drive bleiben erhalten.")
            }
        }
        .navigationTitle("Datensicherung")
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: pickerPurpose == .folder ? [.folder] : Self.importTypes) { result in
            switch pickerPurpose {
            case .folder:
                switch result {
                case .success(let url):
                    backup.setFolder(url)
                    if backup.encryptBackups && !backup.hasPassword { passwordSheet = true }
                case .failure(let e):
                    message = "Ordner konnte nicht ausgewählt werden: \(e.localizedDescription)"
                }
            case .importFile:
                handleImportPick(result)
            }
        }
        .sheet(isPresented: $passwordSheet) { BackupPasswordView() }
        .sheet(item: Binding(get: { decoded.map(IdentifiedPayload.init) }, set: { if $0 == nil { decoded = nil } })) { item in
            ImportOptionsView(payload: item.payload) { mode in
                model.importData(item.payload.data, mode: mode)
                decoded = nil
                message = "Import abgeschlossen."
            }
        }
        .alert("Backup-Passwort", isPresented: $askImportPassword) {
            SecureField("Passwort", text: $importPassword)
            Button("Entschlüsseln") { decodeImport() }
            Button("Abbrechen", role: .cancel) { importData = nil }
        } message: {
            Text("Dieses Backup ist verschlüsselt.")
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Snapshot wiederherstellen?", isPresented: Binding(get: { snapshotToRestore != nil }, set: { if !$0 { snapshotToRestore = nil } }),
                            titleVisibility: .visible, presenting: snapshotToRestore) { snap in
            Button("Wiederherstellen", role: .destructive) { restoreSnapshot(snap) }
        } message: { snap in
            Text("Der aktuelle Stand wird durch den Snapshot vom \(snap.date.formatted(date: .long, time: .omitted)) ersetzt. Vorher wird ein Sicherheits-Snapshot des aktuellen Stands angelegt.")
        }
        .confirmationDialog("Wirklich alle Daten löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Weiter", role: .destructive) { confirmWipe2 = true }
        }
        .alert("Endgültig löschen?", isPresented: $confirmWipe2) {
            Button("Alles löschen", role: .destructive) { model.wipeAllData() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Diese Aktion kann nicht rückgängig gemacht werden – außer über ein externes Backup.")
        }
    }

    static var importTypes: [UTType] {
        var t: [UTType] = [.json, .zip, .data]
        if let b = UTType(filenameExtension: "nfpbackup") { t.insert(b, at: 0) }
        return t
    }

    // MARK: Abschnitte

    private var statusSection: some View {
        Section {
            LabeledContent("Erfasste Tage", value: "\(model.data.days.count)")
            LabeledContent("Zyklen", value: "\(model.cycles.count)")
            if let s = model.lastSavedAt {
                LabeledContent("Zuletzt gespeichert", value: s.germanDateTime)
            }
            if let err = model.saveError {
                Text(err).foregroundStyle(.red)
            }
            LabeledContent("Externe Sicherung", value: backup.lastExternalBackup?.germanRelative ?? "noch nie")
        } header: {
            Text("Status")
        } footer: {
            Text("Deine Daten werden nur auf diesem iPhone gespeichert – verschlüsselt durch den iOS-Datenschutz und mit Prüfsumme. Bei einer beschädigten Datei stellt die App automatisch den letzten gültigen Stand wieder her. Ist iCloud-Backup für dein iPhone aktiv, sind die App-Daten auch dort enthalten.")
        }
    }

    private var autoBackupSection: some View {
        @Bindable var backup = backup
        return Section {
            Button {
                pickerPurpose = .folder
                showPicker = true
            } label: {
                LabeledContent("Backup-Ordner", value: backup.folderName ?? "auswählen …")
            }
            if backup.hasFolder {
                Toggle("Automatisch sichern", isOn: $backup.autoBackupEnabled)
                Toggle("Backups verschlüsseln (empfohlen)", isOn: $backup.encryptBackups)
                if backup.encryptBackups {
                    Button(backup.hasPassword ? "Backup-Passwort ändern" : "Backup-Passwort festlegen") { passwordSheet = true }
                        .foregroundStyle(backup.hasPassword ? Theme.accent : .orange)
                }
                Stepper("Tages-Backups behalten: \(backup.keepCount)", value: $backup.keepCount, in: 3...365)
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await backup.backupNow(data: model.data)
                            message = "Backup erfolgreich gespeichert."
                        } catch {
                            message = backup.lastError ?? error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        Text("Jetzt sichern")
                        if busy || backup.isRunning { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isDemo)
                if let d = backup.lastBackupDate {
                    LabeledContent("Letztes Backup", value: d.germanDateTime)
                }
                if let e = backup.lastError {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }
                NavigationLink("Backups im Ordner anzeigen") {
                    FolderBackupsView { data in startImport(data) }
                }
                Button("Ordner-Verknüpfung entfernen", role: .destructive) { backup.clearFolder() }
            }
        } header: {
            Text("Automatisches Backup (iCloud Drive)")
        } footer: {
            Text("Tippe auf „Backup-Ordner“, öffne in iCloud Drive den gewünschten Ordner (oder lege mit dem Ordner-Symbol einen neuen an) und tippe oben rechts auf „Öffnen“. Die App legt dort nach jeder Änderung „NFP-Backup-aktuell“ und täglich ein datiertes Backup ab. So sind deine Daten auch bei Verlust oder Defekt des iPhones geschützt. Notiere dir das Backup-Passwort – ohne es lassen sich verschlüsselte Backups nicht wiederherstellen.")
        }
    }

    private var snapshotSection: some View {
        Section {
            let snaps = model.store.listSnapshots()
            if snaps.isEmpty {
                Text("Noch keine Snapshots.").foregroundStyle(.secondary)
            }
            ForEach(snaps) { s in
                Button {
                    snapshotToRestore = s
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.isSafety ? s.date.formatted(date: .abbreviated, time: .shortened) : s.date.formatted(date: .complete, time: .omitted))
                            if s.isSafety { Text("Sicherheits-Snapshot vor Import/Löschen").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(s.size), countStyle: .file))
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
                .disabled(model.isDemo)
            }
        } header: {
            Text("Lokale Snapshots")
        } footer: {
            Text("Automatisch einmal täglich: die letzten 7 Tage und je ein Snapshot pro Monat für 12 Monate, dazu Sicherheits-Snapshots vor Import, Wiederherstellung und Löschen. Tippe zum Wiederherstellen.")
        }
    }

    private var exportSection: some View {
        Section {
            SecureField("Passwort (optional, verschlüsselt den Export)", text: $exportPassword)
            Button("Export erstellen") { createExport() }
                .disabled(model.isDemo)
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export teilen / in Dateien sichern", systemImage: "square.and.arrow.up")
                }
            }
            if let exportError { Text(exportError).foregroundStyle(.red) }
        } header: {
            Text("Zyklusdaten exportieren")
        } footer: {
            Text("ZIP-Archiv mit CSV-Dateien (UTF-8, z. B. für Excel), den App-Einstellungen und einer Backup-Datei für den Import. Mit Passwort enthält das Archiv nur das verschlüsselte Backup. Empfehlung: mindestens monatlich exportieren, falls kein automatisches Backup aktiv ist.")
        }
    }

    private var importSection: some View {
        Section {
            Button("Backup oder Export importieren …") {
                pickerPurpose = .importFile
                showPicker = true
            }
                .disabled(model.isDemo)
        } header: {
            Text("Import / Wiederherstellung")
        } footer: {
            Text("Unterstützt .nfpbackup-Dateien, Export-ZIPs und JSON-Backups dieser App. Vor jedem Import wird ein Sicherheits-Snapshot angelegt.")
        }
    }

    // MARK: Aktionen

    private func createExport() {
        do {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            let zip = try DataExporter.exportZip(data: model.data, cycles: model.cycles, evaluations: model.evaluations,
                                                 appVersion: version, password: exportPassword.isEmpty ? nil : exportPassword)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("NFP-Export-\(f.string(from: Date())).zip")
            try zip.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
            exportError = nil
            backup.noteExport()
        } catch {
            exportError = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func handleImportPick(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            importError = e.localizedDescription
        case .success(let url):
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                startImport(try Data(contentsOf: url))
            } catch {
                importError = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    private func startImport(_ data: Data) {
        importData = data
        importPassword = backup.password ?? ""
        if BackupCodec.needsPassword(data) {
            // Gespeichertes Backup-Passwort zuerst versuchen
            if let pw = backup.password, let p = try? BackupCodec.decode(data, password: pw) {
                decoded = p
                importData = nil
            } else {
                importPassword = ""
                askImportPassword = true
            }
        } else {
            decodeImport()
        }
    }

    private func decodeImport() {
        guard let data = importData else { return }
        do {
            decoded = try BackupCodec.decode(data, password: importPassword)
            importData = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func restoreSnapshot(_ s: DataStore.SnapshotInfo) {
        do {
            let d = try model.store.loadSnapshot(s)
            model.replaceAll(with: d)
            message = "Snapshot wiederhergestellt."
        } catch {
            message = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct IdentifiedPayload: Identifiable {
    let payload: BackupPayload
    var id: Date { payload.createdAt }
}

/// Auswahl, wie ein Backup importiert werden soll
struct ImportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let payload: BackupPayload
    let onImport: (ImportMode) -> Void
    @State private var mode: ImportMode = .replace

    var body: some View {
        NavigationStack {
            Form {
                Section("Inhalt des Backups") {
                    LabeledContent("Erstellt", value: payload.createdAt.germanDateTime)
                    if let d = payload.deviceName { LabeledContent("Gerät", value: d) }
                    LabeledContent("Tage", value: "\(payload.data.days.count)")
                    if let first = payload.data.days.keys.min(), let last = payload.data.days.keys.max() {
                        LabeledContent("Zeitraum", value: "\(first.german) – \(last.german)")
                    }
                    LabeledContent("Kataloge", value: "\(payload.data.catalogs.count)")
                }
                Section {
                    Picker("Art des Imports", selection: $mode) {
                        ForEach(ImportMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text("„Ersetzen“ übernimmt auch Einstellungen und Kataloge des Backups. Vor dem Import wird automatisch ein Snapshot des aktuellen Stands angelegt.")
                }
            }
            .navigationTitle("Importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") {
                        onImport(mode)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BackupPasswordView: View {
    @Environment(BackupService.self) private var backup
    @Environment(\.dismiss) private var dismiss
    @State private var pw1 = ""
    @State private var pw2 = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passwort", text: $pw1)
                    SecureField("Passwort wiederholen", text: $pw2)
                } footer: {
                    Text("Mindestens 8 Zeichen. Das Passwort wird sicher in der Keychain dieses iPhones gespeichert, damit automatische Backups funktionieren. Für die Wiederherstellung auf einem neuen iPhone brauchst du es – notiere es dir an einem sicheren Ort.")
                }
                if !pw2.isEmpty && pw1 != pw2 {
                    Text("Die Passwörter stimmen nicht überein.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Backup-Passwort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        backup.setPassword(pw1)
                        dismiss()
                    }
                    .disabled(pw1.count < 8 || pw1 != pw2)
                }
            }
        }
    }
}

/// Backups im gewählten Ordner
struct FolderBackupsView: View {
    @Environment(BackupService.self) private var backup
    let onRestore: (Data) -> Void
    @State private var files: [URL] = []
    @State private var error: String?

    var body: some View {
        List {
            if files.isEmpty {
                Text("Keine Backups gefunden.").foregroundStyle(.secondary)
            }
            ForEach(files, id: \.self) { url in
                Button {
                    do { onRestore(try backup.readBackup(url)) } catch { self.error = error.localizedDescription }
                } label: {
                    Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.badge.clock")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Backups")
        .onAppear { files = backup.listBackups() }
    }
}
