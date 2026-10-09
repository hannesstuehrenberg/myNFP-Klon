import Foundation

/// Ergebnis der Höhepunkt-Auswertung (Zervixschleim oder Muttermund).
public struct PeakResult: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case none
        /// Möglicher Höhepunkt, die 3 Folgetage stehen noch aus
        case pending
        case completed
        /// Auswertung nicht möglich (z. B. fehlende Einträge bei strenger Auswertung)
        case failed
    }

    public var status: Status = .none
    public var peakDay: Int?
    /// Tage 1, 2, 3 nach dem Höhepunkt
    public var afterPeakDays: [Int] = []
    /// Ab dem Abend dieses Tages abgeschlossen (= 3. Tag nach dem Höhepunkt)
    public var completionDay: Int?
    public var log: [ProtocolEntry] = []

    public init() {}
}

/// Gemeinsame Logik für Schleim- und Muttermund-Höhepunkt.
struct PeakEvaluator {
    enum Observation {
        case missing
        case value(Int)
    }

    /// Name für das Protokoll, z. B. „Zervixschleim“
    let name: String
    /// Beobachtung pro Zyklustag (Index 0 = ZT 1)
    let observations: [Observation]
    /// Nur Tage mit mindestens dieser Qualität kommen als Höhepunkt in Frage
    let minimumPeakQuality: Int
    /// Schleim: Höhepunkt muss die bisher beste Qualität haben. Muttermund: jeder fruchtbare Tag kommt in Frage.
    let requiresBestSoFar: Bool
    /// Bedingung für die 3 Tage nach dem Höhepunkt
    let isAfterPeakOK: (_ quality: Int, _ peakQuality: Int) -> Bool
    /// Erneuter Anstieg, der den Höhepunkt ungültig macht
    let isReRise: (_ quality: Int, _ peakQuality: Int) -> Bool
    /// Bei laxer Auswertung zählt ein Tag ohne Eintrag wie die schlechteste Qualität
    let lax: Bool
    let worstQuality: Int
    let describe: (Int) -> String

    /// - Parameter temperatureCompletionDay: Abschluss der Temperaturauswertung (falls vorhanden)
    func evaluate(temperatureCompletionDay: Int?) -> PeakResult {
        var result = PeakResult()
        let lastDataDay = observations.lastIndex { if case .value = $0 { return true } else { return false } }.map { $0 + 1 } ?? 0
        guard lastDataDay > 0 else {
            result.log.append(.info("\(name): keine Einträge."))
            return result
        }

        func quality(_ day: Int) -> Int? {
            guard day >= 1, day <= observations.count else { return nil }
            switch observations[day - 1] {
            case .value(let q): return q
            case .missing: return (lax && day <= lastDataDay) ? worstQuality : nil
            }
        }

        var maxSoFar = Int.min
        var day = 1
        candidateLoop: while day <= lastDataDay {
            defer { day += 1 }
            guard let q = quality(day) else { continue }
            let isCandidate = q >= minimumPeakQuality && (!requiresBestSoFar || q >= maxSoFar)
            maxSoFar = max(maxSoFar, q)
            guard isCandidate else { continue }

            // Prüfe die 3 Folgetage
            var after: [Int] = []
            for k in 1...3 {
                let d = day + k
                if d > lastDataDay {
                    // Folgetage liegen in der Zukunft → möglicher Höhepunkt
                    result.status = .pending
                    result.peakDay = day
                    result.afterPeakDays = after
                    result.log.append(.info("\(name): möglicher Höhepunkt an ZT \(day) (\(describe(q))), Folgetage stehen noch aus."))
                    return result
                }
                guard let qa = quality(d) else {
                    result.log.append(.warning("\(name): möglicher Höhepunkt an ZT \(day) nicht bestätigbar – an ZT \(d) fehlt ein Eintrag."))
                    continue candidateLoop
                }
                if !isAfterPeakOK(qa, q) { continue candidateLoop }
                after.append(d)
            }

            let completion = day + 3
            // Erneuter Anstieg vor Abschluss der Doppelkontrolle macht den Höhepunkt ungültig
            let checkUntil = min(max(completion, temperatureCompletionDay ?? lastDataDay), lastDataDay)
            if checkUntil > completion {
                for e in (completion + 1)...checkUntil {
                    guard let qe = quality(e) else {
                        result.status = .failed
                        result.peakDay = day
                        result.afterPeakDays = after
                        result.log.append(.warning("\(name): Für die strenge Auswertung fehlt ein Eintrag an ZT \(e) (vom Höhepunkt bis zum Abschluss der Temperaturauswertung ist an jedem Tag ein Eintrag nötig)."))
                        return result
                    }
                    if isReRise(qe, q) {
                        result.log.append(.info("\(name): Höhepunkt an ZT \(day) verworfen, da an ZT \(e) erneut \(describe(qe)) auftritt."))
                        // Weiter suchen ab Tag e (als neuer Kandidat)
                        maxSoFar = Int.min
                        day = e - 1
                        continue candidateLoop
                    }
                }
            }

            result.status = .completed
            result.peakDay = day
            result.afterPeakDays = after
            result.completionDay = completion
            result.log.append(.rule("\(name)-Höhepunkt an ZT \(day) (\(describe(q))), gefolgt von 3 Tagen schlechterer Qualität (ZT \(after.map(String.init).joined(separator: ", ")))."))
            result.log.append(.result("\(name)auswertung abgeschlossen am Abend von ZT \(completion)."))
            return result
        }
        result.log.append(.info("\(name): kein Höhepunkt gefunden."))
        return result
    }
}

extension PeakEvaluator {
    static func mucus(cycle: Cycle, lastObservedDay: Int, lax: Bool, subdifferentiation: Bool) -> PeakEvaluator {
        let obs: [Observation] = cycle.entries.enumerated().map { i, e in
            guard i < lastObservedDay, let m = e?.mucus, var rank = m.qualityRank else { return .missing }
            if !subdifferentiation, m.reduced, let s = m.symbol { rank = s.rawValue * 2 }
            return .value(rank)
        }
        return PeakEvaluator(
            name: "Zervixschleim",
            observations: obs,
            minimumPeakQuality: MucusSymbol.f.rawValue * 2,
            requiresBestSoFar: true,
            isAfterPeakOK: { qa, qp in qa < qp },
            isReRise: { qe, qp in qe >= qp },
            lax: lax,
            worstQuality: 0,
            describe: { rank in
                let base = MucusSymbol(rawValue: (rank + 1) / 2) ?? .t
                return rank % 2 == 1 ? "(\(base.label))" : base.label
            }
        )
    }

    static func cervix(cycle: Cycle, lastObservedDay: Int, lax: Bool) -> PeakEvaluator {
        let obs: [Observation] = cycle.entries.enumerated().map { i, e in
            guard i < lastObservedDay, let c = e?.cervix, let score = c.fertilityScore else { return .missing }
            // Geschlossen und hart zählt als 0, egal welche Position
            return .value(c.isClosedAndHard ? 0 : score)
        }
        return PeakEvaluator(
            name: "Muttermund",
            observations: obs,
            minimumPeakQuality: 1,
            requiresBestSoFar: false,
            isAfterPeakOK: { qa, _ in qa == 0 },
            isReRise: { qe, _ in qe > 0 },
            lax: lax,
            worstQuality: 0,
            describe: { $0 == 0 ? "geschlossen und hart" : "geöffnet bzw. weich" }
        )
    }
}
