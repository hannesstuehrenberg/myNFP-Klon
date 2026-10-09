import SwiftUI
import NFPCore

/// Reiter „Mehr“
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(BackupService.self) private var backup
    @Environment(AppLock.self) private var lock

    var body: some View {
        NavigationStack {
            List {
                if needsBackupHint {
                    Section {
                        NavigationLink {
                            BackupView()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Datensicherung einrichten").font(.subheadline.weight(.semibold))
                                    Text(backup.lastExternalBackup.map { "Letzte externe Sicherung \($0.germanRelative)." }
                                         ?? "Deine Daten liegen bisher nur auf diesem iPhone.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section("Zyklusdaten") {
                    NavigationLink { CatalogsView() } label: { Label("Kataloge", systemImage: "folder") }
                    NavigationLink { DayDataSettingsView() } label: { Label("Tagesdaten-Einstellungen", systemImage: "slider.horizontal.3") }
                    NavigationLink { SearchView() } label: { Label("Suche", systemImage: "magnifyingglass") }
                    NavigationLink { NotesTableView() } label: { Label("Tabelle mit Notizen", systemImage: "tablecells") }
                }

                Section("Datensicherung") {
                    NavigationLink { BackupView() } label: {
                        Label("Backup, Export & Import", systemImage: "externaldrive.badge.icloud")
                    }
                }

                Section("Einstellungen") {
                    NavigationLink { AppSettingsView() } label: { Label("App-Einstellungen", systemImage: "gearshape") }
                    NavigationLink { LockSettingsView() } label: {
                        Label {
                            HStack {
                                Text("Code-Sperre")
                                Spacer()
                                Text(lock.isEnabled ? "an" : "aus").foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "lock") }
                    }
                    NavigationLink { NotificationSettingsView() } label: { Label("Benachrichtigungen", systemImage: "bell") }
                }

                Section("Wissen") {
                    NavigationLink { KnowledgeListView() } label: { Label("NFP-Regeln & Zykluswissen", systemImage: "book") }
                    NavigationLink {
                        List { LegendContent() }.navigationTitle("Farben & Symbole")
                    } label: { Label("Farben & Symbole", systemImage: "paintpalette") }
                    NavigationLink { DisclaimerView(showsAccept: false) } label: { Label("Zweckbestimmung & Hinweise", systemImage: "cross.case") }
                }

                Section {
                    if model.isDemo {
                        Button("Demo-Modus beenden") { model.exitDemo() }
                    } else {
                        Button("Demo-Modus starten") { model.enterDemo() }
                    }
                } footer: {
                    Text("Im Demo-Modus siehst du die App mit Beispieldaten. Deine eigenen Daten bleiben unverändert; im Demo-Modus wird nichts gespeichert.")
                }

                Section {
                    NavigationLink { AboutView() } label: { Label("Über diese App", systemImage: "info.circle") }
                }
            }
            .navigationTitle("Mehr")
        }
    }

    private var needsBackupHint: Bool {
        guard !model.isDemo, model.data.days.count > 7 else { return false }
        guard let last = backup.lastExternalBackup else { return true }
        return Date().timeIntervalSince(last) > 30 * 86400
    }
}
