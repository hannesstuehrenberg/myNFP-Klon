import SwiftUI
import NFPCore

/// Kataloge: „Ordner für Zyklusblätter“, z. B. für Pausen nach Schwangerschaft oder hormoneller Verhütung.
struct CatalogsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Catalog?
    @State private var creating = false
    @State private var deleteCandidate: Catalog?

    var body: some View {
        List {
            Section {
                ForEach(model.data.catalogs) { cat in
                    Button {
                        editing = cat
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(cat.name).font(.headline)
                                    if cat.id == model.data.mainCatalog.id {
                                        Text("Hauptkatalog").font(.caption2.bold())
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Theme.accent.opacity(0.2)))
                                    }
                                }
                                Text(detail(cat)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if model.data.catalogs.count > 1 {
                            Button("Löschen", role: .destructive) { deleteCandidate = cat }
                        }
                    }
                }
                .onMove { model.moveCatalogs(from: $0, to: $1) }
            } footer: {
                Text("Jeder Katalog wird getrennt ausgewertet – es fließen nur Zyklen desselben Katalogs in die Auswertung ein. In den meisten Fällen genügt ein einziger Katalog. Der oberste Katalog ist der Hauptkatalog.")
            }
        }
        .navigationTitle("Kataloge")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Katalog hinzufügen")
            }
        }
        .sheet(item: $editing) { cat in CatalogEditView(catalog: cat, isNew: false) }
        .sheet(isPresented: $creating) {
            CatalogEditView(catalog: Catalog(name: "Neuer Katalog", priorEarliestFirstHigher: earliestOverall), isNew: true)
        }
        .confirmationDialog("Katalog löschen?", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                            titleVisibility: .visible, presenting: deleteCandidate) { cat in
            Button("„\(cat.name)“ löschen", role: .destructive) { model.deleteCatalog(cat) }
        } message: { _ in
            Text("Die Zyklen dieses Katalogs werden dem Hauptkatalog zugeordnet. Tagesdaten werden nicht gelöscht.")
        }
    }

    private func detail(_ c: Catalog) -> String {
        var parts = ["\(model.cycleCount(in: c)) Zyklen"]
        if c.priorCycleCount > 0 { parts.append("+\(c.priorCycleCount) frühere") }
        if c.postPill { parts.append("Post-Pill") }
        if let e = c.priorEarliestFirstHigher { parts.append("früheste 1.hM \(e)") }
        return parts.joined(separator: " · ")
    }

    /// Früheste 1.hM aus allen Katalogen (wird beim neuen Katalog vorgeschlagen)
    private var earliestOverall: Int? {
        let fromEvaluations = model.evaluations.values.compactMap { $0.temperature.status == .completed ? $0.temperature.firstHigherDay : nil }
        let fromCatalogs = model.data.catalogs.compactMap(\.priorEarliestFirstHigher)
        return (fromEvaluations + fromCatalogs).min()
    }
}

struct CatalogEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var catalog: Catalog
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $catalog.name)
                }
                Section {
                    Stepper("Frühere Zyklen: \(catalog.priorCycleCount)", value: $catalog.priorCycleCount, in: 0...500)
                    OptionalNumberField(title: "Früheste 1. höhere Messung (ZT)", value: $catalog.priorEarliestFirstHigher, range: 8...40)
                } header: {
                    Text("Frühere Aufzeichnungen")
                } footer: {
                    Text("Anzahl der Zyklen mit 1. höherer Messung, die du z. B. auf Papier oder in einer anderen App ausgewertet hast. Ab 12 Zyklen darf die Minus-8-Regel verlängert werden. Die früheste 1. höhere Messung gilt ein Leben lang.")
                }
                Section {
                    OptionalNumberField(title: "Kürzester Zyklus (Minus-20)", value: $catalog.shortestCycleForMinus20, range: 15...60)
                } footer: {
                    Text("Nur wenn du die Längen deiner letzten 12 Zyklen kennst und vorher nicht hormonell verhütet hast. Kürzester Zyklus − 20 = unfruchtbare Tage am Zyklusanfang. Nach 12 Zyklen mit Temperatur gilt die Minus-8-Regel.")
                }
                Section {
                    Toggle("Post-Pill", isOn: $catalog.postPill)
                } footer: {
                    Text("Unmittelbar vor Beginn der Aufzeichnungen hormonell verhütet: Fruchtbarkeit ab dem 1. Zyklustag und ein zusätzlicher höherer Temperaturwert, bis in einem Zyklus eine 1. höhere Messung bestätigt wurde.")
                }
                Section {
                    Stepper("Prognose verschieben: \(catalog.periodForecastShift > 0 ? "+" : "")\(catalog.periodForecastShift) Tage",
                            value: $catalog.periodForecastShift, in: -5...5)
                    Toggle("Temperaturskala fixieren", isOn: $catalog.fixedTemperatureScale)
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("Fixierte Skala: gleiche Temperaturachse für alle Zyklen dieses Katalogs, sonst dynamisch pro Zyklus.")
                }
                Section("Kommentar") {
                    TextField("Kommentar", text: Binding(get: { catalog.comment ?? "" }, set: { catalog.comment = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                }
            }
            .navigationTitle(isNew ? "Neuer Katalog" : "Katalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if isNew { model.addCatalog(catalog) } else { model.updateCatalog(catalog) }
                        dismiss()
                    }
                    .disabled(catalog.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct OptionalNumberField: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>

    var body: some View {
        Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? range.lowerBound + (range.upperBound - range.lowerBound) / 3) : nil }))
        if let v = value {
            Stepper(value: Binding(get: { v }, set: { value = $0 }), in: range) {
                Text("\(v)").monospacedDigit()
            }
        }
    }
}
