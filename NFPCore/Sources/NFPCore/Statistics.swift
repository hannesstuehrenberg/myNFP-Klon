import Foundation

public struct CycleStatRow: Hashable, Sendable, Identifiable {
    public var id: LocalDate { start }
    public var start: LocalDate
    public var end: LocalDate
    public var length: Int
    public var isCompleted: Bool
    public var catalogName: String
    public var firstHigherDay: Int?
    public var isEarliestFirstHigher: Bool
    public var mucusPeakDay: Int?
    public var cervixPeakDay: Int?
    public var highPhaseLength: Int?
    public var infertileStartUntil: Int
    public var startRule: StartRule
    public var infertileFromEvening: Int?
    public var wantsChild: Bool
    public var hasComment: Bool
    public var bleedingDays: Int
}

public struct StatisticsSummary: Hashable, Sendable {
    public var cycleCount: Int
    public var completedCount: Int
    public var averageLength: Double?
    public var shortest: Int?
    public var longest: Int?
    public var averageHighPhase: Double?
    public var shortestHighPhase: Int?
    public var longestHighPhase: Int?
    public var earliestFirstHigher: Int?
    public var latestFirstHigher: Int?
    public var averageFirstHigher: Double?
    public var averageBleedingDays: Double?
    public var cyclesWithFirstHigher: Int
}

public enum Statistics {
    public static func rows(cycles: [Cycle], evaluations: [LocalDate: CycleEvaluation], data: AppData) -> [CycleStatRow] {
        cycles.compactMap { c in
            guard let ev = evaluations[c.startDate] else { return nil }
            let tempDone = ev.temperature.status == .completed
            return CycleStatRow(
                start: c.startDate,
                end: c.endDate,
                length: c.length,
                isCompleted: c.isCompleted,
                catalogName: data.catalog(id: c.meta.catalogID).name,
                firstHigherDay: tempDone ? ev.temperature.firstHigherDay : nil,
                isEarliestFirstHigher: ev.isEarliestFirstHigher,
                mucusPeakDay: ev.mucus.status == .completed ? ev.mucus.peakDay : nil,
                cervixPeakDay: ev.cervix.status == .completed ? ev.cervix.peakDay : nil,
                highPhaseLength: ev.highPhaseLength,
                infertileStartUntil: ev.startPhase.infertileUntilDay,
                startRule: ev.startPhase.rule,
                infertileFromEvening: ev.infertileFromEveningOfDay,
                wantsChild: c.meta.wantsChild,
                hasComment: !(c.meta.comment?.isEmpty ?? true),
                bleedingDays: bleedingDays(c)
            )
        }
    }

    /// Anzahl der Blutungstage am Zyklusanfang (zusammenhängend, ohne Schmierblutung am Ende)
    public static func bleedingDays(_ c: Cycle) -> Int {
        var n = 0
        for e in c.entries {
            guard let b = e?.bleeding else { break }
            if b == .spotting && n > 0 { break }
            n += 1
        }
        return n
    }

    public static func summary(_ rows: [CycleStatRow]) -> StatisticsSummary {
        let completed = rows.filter(\.isCompleted)
        let lengths = completed.map(\.length)
        let highs = completed.compactMap(\.highPhaseLength)
        let fhms = rows.compactMap(\.firstHigherDay)
        let bleeding = completed.map(\.bleedingDays).filter { $0 > 0 }
        func avg(_ a: [Int]) -> Double? { a.isEmpty ? nil : Double(a.reduce(0, +)) / Double(a.count) }
        return StatisticsSummary(
            cycleCount: rows.count,
            completedCount: completed.count,
            averageLength: avg(lengths),
            shortest: lengths.min(),
            longest: lengths.max(),
            averageHighPhase: avg(highs),
            shortestHighPhase: highs.min(),
            longestHighPhase: highs.max(),
            earliestFirstHigher: fhms.min(),
            latestFirstHigher: fhms.max(),
            averageFirstHigher: avg(fhms),
            averageBleedingDays: avg(bleeding),
            cyclesWithFirstHigher: fhms.count
        )
    }
}

// MARK: - Periodenkalender-Prognose

public struct PredictedPeriod: Hashable, Sendable, Identifiable {
    public var id: LocalDate { earliestStart }
    /// Frühester/spätester erwarteter Beginn
    public var earliestStart: LocalDate
    public var latestStart: LocalDate
    /// Wahrscheinlichster Beginn
    public var likelyStart: LocalDate
    public var bleedingDays: Int
    /// Basierend auf Temperaturanstieg (genauer) oder nur auf Zykluslängen
    public var basedOnTemperature: Bool
}

public enum PeriodPredictor {
    /// Prognose der nächsten Perioden unter Berücksichtigung der natürlichen Zyklusschwankung.
    public static func predict(cycles: [Cycle], evaluations: [LocalDate: CycleEvaluation], count: Int = 6) -> [PredictedPeriod] {
        guard let current = cycles.last, !current.isCompleted else { return [] }
        let currentCatalog = current.meta.catalogID
        let history = cycles.filter { $0.isCompleted && $0.meta.catalogID == currentCatalog }.suffix(12)
        let lengths = history.map(\.length).filter { $0 >= 15 && $0 <= 60 }
        let bleedingHistory = history.map(Statistics.bleedingDays).filter { $0 > 0 }
        let bleedingDays = bleedingHistory.isEmpty ? 5 : Int((Double(bleedingHistory.reduce(0, +)) / Double(bleedingHistory.count)).rounded())

        let mean: Double
        let sd: Double
        if lengths.isEmpty {
            mean = 28; sd = 3
        } else {
            mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
            if lengths.count > 1 {
                let v = lengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(lengths.count - 1)
                sd = max(1.5, sqrt(v))
            } else {
                sd = 3
            }
        }

        var result: [PredictedPeriod] = []
        var likely: Double
        var spread: Double
        var basedOnTemp = false
        if let f = evaluations[current.startDate]?.periodForecast {
            let mid = Double(f.earliest.dayNumber + f.latest.dayNumber) / 2
            likely = mid
            spread = Double(f.latest.dayNumber - f.earliest.dayNumber) / 2
            basedOnTemp = true
        } else {
            likely = Double(current.startDate.dayNumber) + mean
            spread = sd
            // Liegt die Prognose bereits in der Vergangenheit, auf morgen verschieben
            let tomorrow = Double(LocalDate.today.dayNumber + 1)
            if likely < tomorrow { likely = tomorrow; spread = max(spread, 2) }
        }
        for k in 0..<count {
            let s = k == 0 ? spread : sqrt(spread * spread + Double(k) * sd * sd)
            let l = LocalDate(dayNumber: Int(likely.rounded()))
            result.append(PredictedPeriod(
                earliestStart: LocalDate(dayNumber: Int((likely - s).rounded(.down))),
                latestStart: LocalDate(dayNumber: Int((likely + s).rounded(.up))),
                likelyStart: l,
                bleedingDays: bleedingDays,
                basedOnTemperature: k == 0 && basedOnTemp
            ))
            likely += mean
        }
        return result
    }
}

// MARK: - Suche

public struct SearchHit: Hashable, Sendable, Identifiable {
    public var id: String { "\(date.isoString)-\(field)" }
    public var date: LocalDate
    public var cycleStart: LocalDate?
    public var cycleDay: Int?
    public var field: String
    public var text: String
}

public enum Search {
    public static func search(_ query: String, data: AppData, cycles: [Cycle]) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        let barNames = Dictionary(uniqueKeysWithValues: data.settings.bars.map { ($0.id, $0.name) })
        for entry in data.days.values {
            var fields: [(String, String)] = []
            if let n = entry.note { fields.append(("Notiz", n)) }
            if let m = entry.medication { fields.append(("Medikamente", m)) }
            for (id, v) in entry.bars {
                let name = barNames[id] ?? id
                var parts = v.selections
                if let t = v.text { parts.append(t) }
                if !parts.isEmpty { fields.append((name, parts.joined(separator: ", "))) }
            }
            for d in entry.disturbances { fields.append(("Störung", d.label)) }
            for (field, text) in fields where text.lowercased().contains(q) || field.lowercased().contains(q) {
                let c = CycleBuilder.cycle(containing: entry.date, in: cycles)
                hits.append(SearchHit(date: entry.date, cycleStart: c?.startDate, cycleDay: c?.cycleDay(of: entry.date),
                                      field: field, text: text))
            }
        }
        for (start, meta) in data.cycleMeta {
            if let c = meta.comment, c.lowercased().contains(q) {
                hits.append(SearchHit(date: start, cycleStart: start, cycleDay: 1, field: "Zykluskommentar", text: c))
            }
        }
        return hits.sorted { $0.date > $1.date }
    }
}
