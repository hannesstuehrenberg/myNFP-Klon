import SwiftUI
import NFPCore

/// Zyklusdaten erfassen: Messmethode, Kinderwunsch, Katalog, manuelle Auswertung, Kommentar.
struct CycleSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cycle: Cycle

    @State private var meta = CycleMeta()
    @State private var durationText = ""
    @State private var showNewCatalog = false
    @State private var newCatalogName = ""
    @State private var newCatalogPostPill = false
    @State private var confirmRemoveStart = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Beginn", value: cycle.startDate.german)
                    LabeledContent("Länge", value: "\(cycle.length) Tage\(cycle.isCompleted ? "" : " (läuft)")")
                }

                Section {
                    Picker("Messort", selection: $meta.measurementSite) {
                        Text("–").tag(MeasurementSite?.none)
                        ForEach(MeasurementSite.allCases) { Text($0.label).tag(MeasurementSite?.some($0)) }
                    }
                    HStack {
                        Text("Messdauer")
                        Spacer()
                        TextField("Min.", text: $durationText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("Min.").foregroundStyle(.secondary)
                    }
                    TextField("Thermometer", text: Binding(get: { meta.thermometer ?? "" },
                                                           set: { meta.thermometer = $0.isEmpty ? nil : $0 }))
                } header: {
                    Text("Wie wurde gemessen?")
                } footer: {
                    Text("Thermometer, Messort und Messdauer dürfen nur mit Beginn eines neuen Zyklus gewechselt werden, nicht innerhalb eines Zyklus.")
                }

                Section {
                    Toggle("Kinderwunsch in diesem Zyklus", isOn: $meta.wantsChild)
                } footer: {
                    Text("Der Kinderwunsch ändert nur die Farben im Zyklusblatt, nicht die Auswertung.")
                }

                Section {
                    Picker("Katalog", selection: Binding(get: { meta.catalogID ?? model.data.mainCatalog.id },
                                                          set: { meta.catalogID = $0 })) {
                        ForEach(model.data.catalogs) { Text($0.name).tag($0.id) }
                    }
                    Button("Neuen Katalog ab diesem Zyklus beginnen") { showNewCatalog = true }
                } header: {
                    Text("Katalog")
                } footer: {
                    Text("Nach einer Schwangerschaft oder hormoneller Verhütung beginnt die Minus-8-Regel von vorne – lege dafür einen neuen Katalog an. Folgende Zyklen übernehmen den Katalog automatisch.")
                }

                Section {
                    Toggle("Manuelle Auswertung", isOn: $meta.useManualEvaluation)
                } footer: {
                    Text("Bei manueller Auswertung markierst du die Phasen selbst (Kurve → Zahnrad-Button).")
                }

                Section("Zykluskommentar") {
                    TextField("Kommentar", text: Binding(get: { meta.comment ?? "" },
                                                         set: { meta.comment = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Button("Zyklusbeginn entfernen (mit Vorzyklus zusammenführen)") { confirmRemoveStart = true }
                    Button("Zyklus inkl. aller Tagesdaten löschen", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Zyklus-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        meta.measurementDurationMinutes = Int(durationText)
                        let value = meta
                        model.updateMeta(for: cycle) { $0 = value }
                        dismiss()
                    }
                }
            }
            .onAppear {
                meta = cycle.meta
                durationText = meta.measurementDurationMinutes.map(String.init) ?? ""
            }
            .alert("Neuer Katalog", isPresented: $showNewCatalog) {
                TextField("Name, z. B. „Nach Schwangerschaft 2026“", text: $newCatalogName)
                Button("Mit Post-Pill-Regeln anlegen") { createCatalog(postPill: true) }
                Button("Anlegen") { createCatalog(postPill: false) }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Wurde unmittelbar vorher hormonell verhütet, wähle „Mit Post-Pill-Regeln“.")
            }
            .confirmationDialog("Zyklusbeginn entfernen?", isPresented: $confirmRemoveStart, titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    model.removeCycleStart(cycle)
                    dismiss()
                }
            } message: {
                Text("Die Tagesdaten bleiben erhalten und werden dem vorherigen Zyklus zugeordnet.")
            }
            .confirmationDialog("Zyklus endgültig löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Zyklus und Tagesdaten löschen", role: .destructive) {
                    model.deleteCycleWithData(cycle)
                    dismiss()
                }
            } message: {
                Text("Alle Tagesdaten vom \(cycle.startDate.german) bis \(cycle.endDate.german) werden gelöscht. Ein Snapshot von heute bleibt in der Datensicherung erhalten.")
            }
        }
    }

    private func createCatalog(postPill: Bool) {
        let name = newCatalogName.trimmingCharacters(in: .whitespaces)
        model.startNewCatalog(named: name.isEmpty ? "Katalog \(model.data.catalogs.count + 1)" : name, from: cycle, postPill: postPill)
        newCatalogName = ""
        dismiss()
    }
}
