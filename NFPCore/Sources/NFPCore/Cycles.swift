import Foundation

/// Ein Zyklus vom 1. Zyklustag bis zum Tag vor dem nächsten 1. Zyklustag.
public struct Cycle: Identifiable, Hashable, Sendable {
    public var id: LocalDate { startDate }
    public let startDate: LocalDate
    /// Letzter Tag (inklusive). Beim laufenden Zyklus: heute bzw. letzter Tag mit Daten.
    public let endDate: LocalDate
    /// Abgeschlossen = es folgt ein weiterer Zyklus
    public let isCompleted: Bool
    public let meta: CycleMeta
    /// Tagesdaten, Index 0 = Zyklustag 1
    public let entries: [DayEntry?]

    public init(startDate: LocalDate, endDate: LocalDate, isCompleted: Bool, meta: CycleMeta, entries: [DayEntry?]) {
        self.startDate = startDate
        self.endDate = endDate
        self.isCompleted = isCompleted
        self.meta = meta
        self.entries = entries
    }

    public var length: Int { startDate.days(until: endDate) + 1 }

    public func date(ofDay day: Int) -> LocalDate { startDate.adding(days: day - 1) }

    public func cycleDay(of date: LocalDate) -> Int { startDate.days(until: date) + 1 }

    public func contains(_ date: LocalDate) -> Bool { date >= startDate && date <= endDate }

    public func entry(day: Int) -> DayEntry? {
        guard day >= 1, day <= entries.count else { return nil }
        return entries[day - 1]
    }
}

public enum CycleBuilder {
    /// Leitet alle Zyklen aus den Tagesdaten ab (Tage mit „Ist 1. Zyklustag“).
    public static func cycles(from data: AppData, today: LocalDate = .today) -> [Cycle] {
        let starts = data.days.values.filter(\.isFirstCycleDay).map(\.date).sorted()
        guard !starts.isEmpty else { return [] }
        let lastDataDate = data.days.keys.max() ?? today
        var result: [Cycle] = []
        result.reserveCapacity(starts.count)
        for (i, start) in starts.enumerated() {
            let isLast = i == starts.count - 1
            let end: LocalDate = isLast ? max(today, lastDataDate, start) : starts[i + 1].adding(days: -1)
            var entries: [DayEntry?] = []
            entries.reserveCapacity(start.days(until: end) + 1)
            var d = start
            while d <= end {
                entries.append(data.days[d])
                d = d.adding(days: 1)
            }
            let meta = data.cycleMeta[start] ?? inheritedMeta(for: start, data: data, previousStart: i > 0 ? starts[i - 1] : nil)
            result.append(Cycle(startDate: start, endDate: end, isCompleted: !isLast, meta: meta, entries: entries))
        }
        return result
    }

    /// Ein neuer Zyklus übernimmt Katalog und Messmethode des Vorzyklus (nicht aber Kommentar/Auswertung).
    static func inheritedMeta(for start: LocalDate, data: AppData, previousStart: LocalDate?) -> CycleMeta {
        guard let previousStart else { return CycleMeta(catalogID: data.mainCatalog.id) }
        // Suche die nächste vorhandene Meta-Angabe rückwärts
        let candidates = data.cycleMeta.filter { $0.key <= previousStart }.max { $0.key < $1.key }
        var meta = CycleMeta(catalogID: candidates?.value.catalogID ?? data.mainCatalog.id)
        if let prev = candidates?.value {
            meta.measurementSite = prev.measurementSite
            meta.measurementDurationMinutes = prev.measurementDurationMinutes
            meta.thermometer = prev.thermometer
            meta.wantsChild = prev.wantsChild
        }
        return meta
    }

    /// Zyklus, der ein Datum enthält.
    public static func cycle(containing date: LocalDate, in cycles: [Cycle]) -> Cycle? {
        // binäre Suche über Startdaten
        var lo = 0, hi = cycles.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cycles[mid].startDate > date { hi = mid - 1 }
            else if cycles[mid].endDate < date { lo = mid + 1 }
            else { return cycles[mid] }
        }
        return nil
    }
}
