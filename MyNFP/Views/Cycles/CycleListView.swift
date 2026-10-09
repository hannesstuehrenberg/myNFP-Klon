import SwiftUI
import NFPCore

/// Reiter „Zyklen“: alle Zyklen mit Länge, 1. höherer Messung und ob es die früheste war.
struct CycleListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Cycle?

    var body: some View {
        NavigationStack {
            List {
                if model.cycles.isEmpty {
                    ContentUnavailableView("Keine Zyklen", systemImage: "list.bullet",
                                           description: Text("Lege im Reiter „Kurve“ deinen ersten Zyklus an."))
                }
                ForEach(groupedCatalogs) { group in
                    Section {
                        ForEach(group.cycles.reversed()) { cycle in
                            CycleRow(cycle: cycle, number: model.cycleNumber(cycle), evaluation: model.evaluation(for: cycle)) {
                                editing = cycle
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.chartCycleStart = cycle.startDate
                                model.selectedDate = cycle.contains(model.today) ? model.today : cycle.startDate
                                model.selectedTab = .chart
                            }
                        }
                    } header: {
                        if model.data.catalogs.count > 1 { Text(group.catalog.name) }
                    }
                }
            }
            .navigationTitle("Zyklen")
            .sheet(item: $editing) { c in
                CycleSettingsView(cycle: c)
            }
        }
    }

    struct CatalogGroup: Identifiable {
        let catalog: Catalog
        let cycles: [Cycle]
        var id: UUID { catalog.id }
    }

    private var groupedCatalogs: [CatalogGroup] {
        // Neueste Kataloge (nach letztem Zyklus) zuerst
        var groups: [UUID: [Cycle]] = [:]
        for c in model.cycles { groups[model.data.catalog(id: c.meta.catalogID).id, default: []].append(c) }
        let result: [CatalogGroup] = groups.compactMap { id, cycles in
            guard let cat = model.data.catalogs.first(where: { $0.id == id }) else { return nil }
            return CatalogGroup(catalog: cat, cycles: cycles)
        }
        return result.sorted { a, b in
            (a.cycles.last?.startDate ?? LocalDate(dayNumber: 0)) > (b.cycles.last?.startDate ?? LocalDate(dayNumber: 0))
        }
    }
}

struct CycleRow: View {
    let cycle: Cycle
    let number: Int
    let evaluation: CycleEvaluation?
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Zyklus \(number)").font(.headline)
                    if cycle.meta.wantsChild {
                        Image(systemName: "heart.circle.fill").foregroundStyle(Theme.fertileWish).font(.caption)
                    }
                    if !(cycle.meta.comment ?? "").isEmpty {
                        Image(systemName: "text.bubble").foregroundStyle(.secondary).font(.caption)
                    }
                    if cycle.meta.useManualEvaluation {
                        Image(systemName: "hand.raised").foregroundStyle(.orange).font(.caption)
                    }
                    if evaluation?.pregnancy != nil {
                        Image(systemName: "figure.and.child.holdinghands").foregroundStyle(Theme.pregnancy).font(.caption)
                    }
                }
                Text("\(cycle.startDate.german) – \(cycle.isCompleted ? cycle.endDate.german : "heute")")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("\(cycle.length) Tage\(cycle.isCompleted ? "" : " (läuft)")")
                    if let ev = evaluation, let f = ev.temperature.firstHigherDay, ev.temperature.status == .completed {
                        Text("1.hM ZT \(f)")
                            .foregroundStyle(ev.isEarliestFirstHigher ? Theme.higherValues : .primary)
                        if ev.isEarliestFirstHigher {
                            Text("früheste")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.higherValues.opacity(0.2)))
                        }
                    } else {
                        Text("keine 1.hM").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Zyklus-Einstellungen")
        }
    }
}
