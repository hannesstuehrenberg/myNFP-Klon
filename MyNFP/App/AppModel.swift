import Foundation
import Observation
import NFPCore

enum AppTab: Hashable {
    case chart, cycles, calendar, statistics, more
}

/// Zentraler Zustand der App: Daten, abgeleitete Zyklen/Auswertungen und Navigation.
@MainActor
@Observable
final class AppModel {
    private(set) var data: AppData
    private(set) var cycles: [Cycle] = []
    private(set) var evaluations: [LocalDate: CycleEvaluation] = [:]
    private(set) var predictions: [PredictedPeriod] = []
    private(set) var today: LocalDate = .today

    /// Demo-Modus: Beispieldaten im Speicher, nichts wird gespeichert
    private(set) var isDemo = false
    private var stashedRealData: AppData?

    var recoveryMessage: String?
    var saveError: String?
    private(set) var lastSavedAt: Date?

    // Navigation
    var selectedTab: AppTab = .chart
    /// Angezeigter Zyklus im Zyklusblatt (nil = aktueller)
    var chartCycleStart: LocalDate?
    var selectedDate: LocalDate = .today
    /// Tagesdaten-Editor
    var editingDate: LocalDate?

    let store: DataStore
    /// Wird nach jeder Änderung aufgerufen (Backups, Benachrichtigungen)
    var onDataChanged: (() -> Void)?

    init(store: DataStore = DataStore()) {
        self.store = store
        let result = store.load()
        data = result.data
        if let from = result.recoveredFrom {
            recoveryMessage = "Die Datendatei war beschädigt. Deine Daten wurden automatisch aus dem \(from) wiederhergestellt."
        } else if !result.problems.isEmpty && !result.isFirstLaunch {
            recoveryMessage = "Die Daten konnten nicht gelesen werden: \(result.problems.joined(separator: "; ")). Bitte stelle ein Backup wieder her (Mehr → Datensicherung)."
        }
        recompute()
        if !isDemo { store.snapshotIfNeeded(data) }
    }

    // MARK: Ableitungen

    func recompute() {
        today = .today
        cycles = CycleBuilder.cycles(from: data, today: today)
        evaluations = CycleEvaluator.evaluateAll(cycles: cycles, data: data, today: today)
        predictions = PeriodPredictor.predict(cycles: cycles, evaluations: evaluations)
    }

    private var backgroundedAt: Date?

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    /// Bei Tageswechsel neu berechnen; nach 4 Stunden Inaktivität wieder „Heute“ auswählen.
    func refreshIfDayChanged() {
        if let t = backgroundedAt, Date().timeIntervalSince(t) > 4 * 3600 {
            chartCycleStart = nil
            selectedDate = .today
        }
        backgroundedAt = nil
        if LocalDate.today != today {
            if selectedDate == today { selectedDate = .today }
            recompute()
        }
    }

    var settings: AppSettings { data.settings }

    var currentCycle: Cycle? { cycles.last }

    func cycle(containing date: LocalDate) -> Cycle? {
        CycleBuilder.cycle(containing: date, in: cycles)
    }

    func evaluation(for cycle: Cycle) -> CycleEvaluation? { evaluations[cycle.startDate] }

    func cycleNumber(_ cycle: Cycle) -> Int {
        let sameCatalog = cycles.filter { $0.meta.catalogID == cycle.meta.catalogID }
        return (sameCatalog.firstIndex { $0.startDate == cycle.startDate } ?? 0) + 1
            + data.catalog(id: cycle.meta.catalogID).priorCycleCount
    }

    /// Im Zyklusblatt angezeigter Zyklus
    var chartCycle: Cycle? {
        if let s = chartCycleStart, let c = cycles.first(where: { $0.startDate == s }) { return c }
        return cycles.last
    }

    func entry(for date: LocalDate) -> DayEntry {
        data.days[date] ?? DayEntry(date: date)
    }

    // MARK: Änderungen

    private func mutate(_ change: (inout AppData) -> Void) {
        change(&data)
        data.modifiedAt = Date()
        cleanupOrphanMeta()
        recompute()
        persist()
    }

    private func persist() {
        guard !isDemo else { return }
        do {
            try store.save(data)
            store.snapshotIfNeeded(data)
            lastSavedAt = Date()
            saveError = nil
        } catch {
            saveError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
        onDataChanged?()
    }

    /// Entfernt Zyklus-Einstellungen, deren 1. Zyklustag nicht mehr existiert.
    private func cleanupOrphanMeta() {
        let starts = Set(data.days.values.filter(\.isFirstCycleDay).map(\.date))
        for key in data.cycleMeta.keys where !starts.contains(key) {
            data.cycleMeta.removeValue(forKey: key)
        }
    }

    func save(entry: DayEntry) {
        mutate { d in
            let wasStart = d.days[entry.date]?.isFirstCycleDay ?? false
            if entry.hasData {
                d.days[entry.date] = entry
            } else {
                d.days.removeValue(forKey: entry.date)
            }
            // Neuer Zyklus: Einstellungen des Vorzyklus übernehmen, damit nachfolgende Zyklen stabil bleiben
            if entry.isFirstCycleDay && !wasStart && d.cycleMeta[entry.date] == nil {
                let prev = cycles.last { $0.startDate < entry.date }
                var meta = CycleMeta(catalogID: prev?.meta.catalogID ?? d.mainCatalog.id)
                if let p = prev?.meta {
                    meta.measurementSite = p.measurementSite
                    meta.measurementDurationMinutes = p.measurementDurationMinutes
                    meta.thermometer = p.thermometer
                    meta.wantsChild = p.wantsChild
                }
                d.days[entry.date]?.isFirstCycleDay = true
                if d.days[entry.date] != nil { d.cycleMeta[entry.date] = meta }
            }
        }
    }

    func deleteEntry(_ date: LocalDate) {
        mutate { $0.days.removeValue(forKey: date) }
    }

    func updateMeta(for cycle: Cycle, _ change: (inout CycleMeta) -> Void) {
        mutate { d in
            var meta = d.cycleMeta[cycle.startDate] ?? cycle.meta
            change(&meta)
            d.cycleMeta[cycle.startDate] = meta
        }
    }

    /// Startet einen Zyklus an einem Datum (setzt „Ist 1. Zyklustag“, ggf. mit Blutung).
    func startCycle(on date: LocalDate, bleeding: Bleeding? = .medium) {
        var e = entry(for: date)
        e.isFirstCycleDay = true
        if e.bleeding == nil { e.bleeding = bleeding }
        save(entry: e)
        chartCycleStart = date
        selectedDate = date
    }

    /// Entfernt den Zyklusbeginn – die Tage werden dem Vorzyklus zugeschlagen.
    func removeCycleStart(_ cycle: Cycle) {
        mutate { d in
            d.days[cycle.startDate]?.isFirstCycleDay = false
            if let e = d.days[cycle.startDate], !e.hasData { d.days.removeValue(forKey: cycle.startDate) }
            d.cycleMeta.removeValue(forKey: cycle.startDate)
        }
        if chartCycleStart == cycle.startDate { chartCycleStart = nil }
    }

    /// Löscht einen Zyklus inklusive aller Tagesdaten.
    func deleteCycleWithData(_ cycle: Cycle) {
        if !isDemo { store.safetySnapshot(data) }
        mutate { d in
            var date = cycle.startDate
            while date <= cycle.endDate {
                d.days.removeValue(forKey: date)
                date = date.adding(days: 1)
            }
            d.cycleMeta.removeValue(forKey: cycle.startDate)
        }
        chartCycleStart = nil
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        mutate { change(&$0.settings) }
    }

    // MARK: Kataloge

    func addCatalog(_ catalog: Catalog) {
        mutate { $0.catalogs.append(catalog) }
    }

    func updateCatalog(_ catalog: Catalog) {
        mutate { d in
            if let i = d.catalogs.firstIndex(where: { $0.id == catalog.id }) { d.catalogs[i] = catalog }
        }
    }

    func moveCatalogs(from: IndexSet, to: Int) {
        mutate { $0.catalogs.move(fromOffsets: from, toOffset: to) }
    }

    func deleteCatalog(_ catalog: Catalog) {
        guard data.catalogs.count > 1 else { return }
        mutate { d in
            d.catalogs.removeAll { $0.id == catalog.id }
            let main = d.catalogs[0].id
            for (k, v) in d.cycleMeta where v.catalogID == catalog.id {
                d.cycleMeta[k]?.catalogID = main
            }
        }
    }

    func cycleCount(in catalog: Catalog) -> Int {
        cycles.filter { data.catalog(id: $0.meta.catalogID).id == catalog.id }.count
    }

    /// Startet ab einem Zyklus einen neuen Katalog (alle folgenden Zyklen ohne eigene Zuordnung folgen).
    func startNewCatalog(named name: String, from cycle: Cycle, postPill: Bool) {
        let cat = Catalog(name: name, postPill: postPill)
        mutate { d in
            d.catalogs.append(cat)
            var meta = d.cycleMeta[cycle.startDate] ?? cycle.meta
            meta.catalogID = cat.id
            d.cycleMeta[cycle.startDate] = meta
            // Explizite Zuordnungen späterer Zyklen zum alten Katalog ebenfalls verschieben
            let old = cycle.meta.catalogID
            for (k, v) in d.cycleMeta where k > cycle.startDate && v.catalogID == old {
                d.cycleMeta[k]?.catalogID = cat.id
            }
        }
    }

    // MARK: Import / Wiederherstellung

    func replaceAll(with newData: AppData) {
        if !isDemo { store.safetySnapshot(data) }
        mutate { $0 = newData }
        chartCycleStart = nil
    }

    func importData(_ imported: AppData, mode: ImportMode) {
        if !isDemo { store.safetySnapshot(data) }
        let merged = DataMerger.merge(current: data, imported: imported, mode: mode)
        mutate { $0 = merged }
        chartCycleStart = nil
    }

    func wipeAllData() {
        store.safetySnapshot(data)
        try? store.wipe()
        var fresh = AppData()
        fresh.settings.acceptedDisclaimer = true
        mutate { $0 = fresh }
        chartCycleStart = nil
    }

    // MARK: Demo-Modus

    func enterDemo() {
        guard !isDemo else { return }
        stashedRealData = data
        isDemo = true
        data = DemoData.make(today: .today)
        chartCycleStart = nil
        selectedDate = .today
        recompute()
    }

    func exitDemo() {
        guard isDemo else { return }
        if let real = stashedRealData { data = real }
        stashedRealData = nil
        isDemo = false
        chartCycleStart = nil
        selectedDate = .today
        recompute()
    }

    // MARK: Hilfen

    /// Vorschläge für Notizen/Medikamente aus bisherigen Einträgen
    func suggestions(for keyPath: KeyPath<DayEntry, String?>, prefix: String) -> [String] {
        let p = prefix.lowercased()
        var counts: [String: Int] = [:]
        for e in data.days.values {
            guard let t = e[keyPath: keyPath]?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { continue }
            if p.isEmpty || t.lowercased().hasPrefix(p) { counts[t, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key).filter { $0 != prefix }
    }

    /// Temperaturbereich für einen Zyklus (fest pro Katalog oder dynamisch)
    func temperatureRange(for cycle: Cycle) -> ClosedRange<Double> {
        let catalog = data.catalog(id: cycle.meta.catalogID)
        let source: [Cycle] = catalog.fixedTemperatureScale
            ? cycles.filter { data.catalog(id: $0.meta.catalogID).id == catalog.id }
            : [cycle]
        let temps = source.flatMap { $0.entries.compactMap { $0?.temperature } }
        // Ausreißer > 2 °C vom Median abschneiden
        let sorted = temps.sorted()
        let median = sorted.isEmpty ? 36.6 : sorted[sorted.count / 2]
        let filtered = sorted.filter { abs($0 - median) <= 2 }
        var lo = (filtered.min() ?? 36.2) - 0.1
        var hi = (filtered.max() ?? 37.0) + 0.15
        lo = (lo * 10).rounded(.down) / 10
        hi = (hi * 10).rounded(.up) / 10
        if hi - lo < 0.9 {
            let mid = (hi + lo) / 2
            lo = ((mid - 0.45) * 10).rounded(.down) / 10
            hi = lo + 0.9
        }
        return lo...hi
    }
}
