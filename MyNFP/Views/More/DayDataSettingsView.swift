import SwiftUI
import NFPCore

/// Tagesdaten-Einstellungen: Zeilen ein-/ausblenden, Zusatzleisten verwalten und sortieren.
struct DayDataSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editingBar: BarDefinition?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(CoreRow.allCases) { row in
                    Toggle(row.label, isOn: Binding(
                        get: { !model.settings.hiddenCoreRows.contains(row) },
                        set: { show in model.updateSettings { s in
                            if show { s.hiddenCoreRows.remove(row) } else { s.hiddenCoreRows.insert(row) }
                        } }
                    ))
                }
            } header: {
                Text("Symptome")
            } footer: {
                Text("Temperatur, Blutung und Zervixschleim sind für die Auswertung wichtig. Ausgeblendete Zeilen erscheinen weder im Zyklusblatt noch in der Eingabe; vorhandene Daten bleiben erhalten.")
            }

            Section {
                ForEach(model.settings.bars) { bar in
                    HStack {
                        Image(systemName: bar.icon ?? "square.grid.2x2").frame(width: 24).foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(bar.name)
                            Text(bar.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { bar.isVisible },
                            set: { v in model.updateSettings { s in
                                if let i = s.bars.firstIndex(where: { $0.id == bar.id }) { s.bars[i].isVisible = v }
                            } }
                        ))
                        .labelsHidden()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingBar = bar }
                }
                .onMove { from, to in model.updateSettings { $0.bars.move(fromOffsets: from, toOffset: to) } }
                .onDelete { idx in model.updateSettings { $0.bars.remove(atOffsets: idx) } }
                Button {
                    creating = true
                } label: {
                    Label("Eigene Zusatzleiste anlegen", systemImage: "plus")
                }
            } header: {
                Text("Zusatzleisten")
            } footer: {
                Text("Tippe auf eine Leiste, um sie umzubenennen oder ihre Optionen zu ändern. Mit „Bearbeiten“ kannst du die Reihenfolge ändern.")
            }
        }
        .navigationTitle("Tagesdaten-Einstellungen")
        .toolbar { EditButton() }
        .sheet(item: $editingBar) { bar in BarEditView(bar: bar, isNew: false) }
        .sheet(isPresented: $creating) {
            BarEditView(bar: BarDefinition(name: "", kind: .singleChoice, options: ["ja", "nein"]), isNew: true)
        }
    }
}

struct BarEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var bar: BarDefinition
    let isNew: Bool
    @State private var newOption = ""

    static let icons = ["square.grid.2x2", "star", "flag", "drop", "bolt", "leaf", "pills", "cup.and.saucer", "moon",
                        "sun.max", "figure.run", "heart", "brain.head.profile", "thermometer.medium", "scalemass", "text.bubble"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. Kaffee", text: $bar.name)
                }
                Section("Typ") {
                    Picker("Typ", selection: $bar.kind) {
                        ForEach(BarKind.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(!isNew && model.data.days.values.contains { $0.bars[bar.id] != nil })
                }
                if bar.kind.usesOptions {
                    Section("Optionen") {
                        ForEach(bar.options, id: \.self) { Text($0) }
                            .onDelete { bar.options.remove(atOffsets: $0) }
                            .onMove { bar.options.move(fromOffsets: $0, toOffset: $1) }
                        HStack {
                            TextField("Neue Option", text: $newOption)
                            Button("Hinzufügen") {
                                let o = newOption.trimmingCharacters(in: .whitespaces)
                                if !o.isEmpty && !bar.options.contains(o) { bar.options.append(o) }
                                newOption = ""
                            }
                        }
                    }
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(bar.icon == icon ? Theme.accent.opacity(0.25) : Color.clear))
                                .onTapGesture { bar.icon = icon }
                        }
                    }
                }
                Section {
                    Toggle("Im Zyklusblatt und in der Eingabe anzeigen", isOn: $bar.isVisible)
                }
            }
            .navigationTitle(isNew ? "Neue Zusatzleiste" : bar.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let b = bar
                        model.updateSettings { s in
                            if let i = s.bars.firstIndex(where: { $0.id == b.id }) { s.bars[i] = b } else { s.bars.append(b) }
                        }
                        dismiss()
                    }
                    .disabled(bar.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
