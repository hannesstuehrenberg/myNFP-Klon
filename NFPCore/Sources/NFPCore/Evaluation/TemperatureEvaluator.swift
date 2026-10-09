import Foundation

public enum TemperatureRule: String, Codable, Sendable {
    case regular = "Grundregel"
    case exception1 = "1. Ausnahmeregel"
    case exception2 = "2. Ausnahmeregel"
    case manual = "manuell"
}

public struct TemperatureResult: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        /// Keine 1. höhere Messung gefunden
        case none
        /// 1. höhere Messung gefunden, Auswertung noch nicht abgeschlossen
        case pending
        /// Temperaturauswertung abgeschlossen
        case completed
    }

    public var status: Status = .none
    /// Zyklustage der 6 niedrigen Werte
    public var lowDays: [Int] = []
    public var coverline: Double?
    public var firstHigherDay: Int?
    /// Zyklustage der gezählten höheren Messungen (1., 2., 3. …)
    public var higherDays: [Int] = []
    /// Bei der 2. Ausnahmeregel ignorierter Wert auf/unter der Hilfslinie
    public var ignoredDropDay: Int?
    public var rule: TemperatureRule?
    /// Ab dem Abend dieses Tages ist die Temperaturauswertung abgeschlossen
    public var completionDay: Int?
    public var postPillExtraValue: Bool = false
    public var log: [ProtocolEntry] = []

    public init() {}
}

public enum TemperatureEvaluator {
    static let eps = 0.001

    struct Measurement {
        let day: Int
        let value: Double
    }

    /// Wertet die Temperatur eines Zyklus nach Sensiplan aus.
    /// - Parameter postPill: Post-Pill-Regel – es wird ein zusätzlicher höherer Wert benötigt.
    public static func evaluate(cycle: Cycle, postPill: Bool, lastObservedDay: Int? = nil) -> TemperatureResult {
        var values: [Measurement] = []
        let limit = lastObservedDay ?? cycle.entries.count
        for (i, e) in cycle.entries.enumerated() where i < limit {
            if let t = e?.validTemperature { values.append(Measurement(day: i + 1, value: t)) }
        }
        return evaluate(values: values, postPill: postPill)
    }

    static func evaluate(values: [Measurement], postPill: Bool) -> TemperatureResult {
        var result = TemperatureResult()
        result.postPillExtraValue = postPill
        guard values.count > 6 else {
            result.log.append(.info("Temperatur: noch keine 6 niedrigen Werte mit folgendem höheren Wert vorhanden."))
            return result
        }

        for i in 6..<values.count {
            let low = values[(i - 6)..<i]
            let cl = low.map(\.value).max()!
            let candidate = values[i]
            guard candidate.value > cl + eps else { continue }

            let following = Array(values[(i + 1)...])
            let outcome = checkRise(coverline: cl, first: candidate, following: following, postPill: postPill)
            let clText = TemperatureInput.format(cl)
            switch outcome {
            case .completed(let higher, let drop, let rule):
                result.status = .completed
                result.lowDays = low.map(\.day)
                result.coverline = cl
                result.firstHigherDay = candidate.day
                result.higherDays = higher
                result.ignoredDropDay = drop
                result.rule = rule
                result.completionDay = higher.last
                result.log.append(.rule("6 niedrige Werte an ZT \(dayList(result.lowDays)); Hilfslinie bei \(clText) °C."))
                result.log.append(.rule("1. höhere Messung an ZT \(candidate.day)."))
                if let drop { result.log.append(.rule("Wert an ZT \(drop) liegt auf/unter der Hilfslinie und wird nach der 2. Ausnahmeregel nicht berücksichtigt.")) }
                switch rule {
                case .regular:
                    result.log.append(.rule("Grundregel: 3 höhere Werte, der 3. mindestens 0,2 °C über der Hilfslinie."))
                case .exception1:
                    result.log.append(.rule("1. Ausnahmeregel: Der 3. höhere Wert liegt weniger als 0,2 °C über der Hilfslinie, daher wurde ein 4. höherer Wert abgewartet."))
                case .exception2:
                    result.log.append(.rule("2. Ausnahmeregel: Der 3. gezählte höhere Wert liegt mindestens 0,2 °C über der Hilfslinie."))
                case .manual: break
                }
                if postPill {
                    result.log.append(.rule("Post-Pill-Regel: zusätzlicher höherer Wert über der Hilfslinie abgewartet."))
                }
                result.log.append(.result("Temperaturauswertung abgeschlossen am Abend von ZT \(higher.last!)."))
                return result

            case .pending(let higher, let drop):
                result.status = .pending
                result.lowDays = low.map(\.day)
                result.coverline = cl
                result.firstHigherDay = candidate.day
                result.higherDays = higher
                result.ignoredDropDay = drop
                result.log.append(.rule("6 niedrige Werte an ZT \(dayList(result.lowDays)); Hilfslinie bei \(clText) °C."))
                result.log.append(.rule("1. höhere Messung an ZT \(candidate.day). Weitere höhere Werte werden abgewartet."))
                return result

            case .failed(let reason):
                result.log.append(.warning("Möglicher Anstieg an ZT \(candidate.day) (Hilfslinie \(clText) °C) nicht auswertbar: \(reason)"))
                continue
            }
        }
        result.log.append(.info("Temperatur: keine auswertbare 1. höhere Messung gefunden."))
        return result
    }

    enum RiseOutcome {
        case completed(higherDays: [Int], drop: Int?, rule: TemperatureRule)
        case pending(higherDays: [Int], drop: Int?)
        case failed(String)
    }

    static func checkRise(coverline cl: Double, first: Measurement, following: [Measurement], postPill: Bool) -> RiseOutcome {
        func above(_ m: Measurement) -> Bool { m.value > cl + eps }
        func strong(_ m: Measurement) -> Bool { m.value >= cl + 0.2 - eps }
        let extra = postPill ? 1 : 0

        // Benötigte Folge: v1 (= first), v2, v3, …
        let seq = [first] + following
        func v(_ n: Int) -> Measurement? { n - 1 < seq.count ? seq[n - 1] : nil }

        guard let v2 = v(2) else { return .pending(higherDays: [first.day], drop: nil) }
        guard let v3 = v(3) else {
            return .pending(higherDays: above(v2) ? [first.day, v2.day] : [first.day], drop: above(v2) ? nil : v2.day)
        }

        // Fall A: v2 und v3 über der Hilfslinie
        if above(v2) && above(v3) {
            if strong(v3) {
                // Grundregel (+ ggf. Post-Pill-Zusatzwert)
                if extra == 0 { return .completed(higherDays: [first.day, v2.day, v3.day], drop: nil, rule: .regular) }
                guard let v4 = v(4) else { return .pending(higherDays: [first.day, v2.day, v3.day], drop: nil) }
                if above(v4) { return .completed(higherDays: [first.day, v2.day, v3.day, v4.day], drop: nil, rule: .regular) }
                return .failed("Post-Pill-Zusatzwert an ZT \(v4.day) liegt nicht über der Hilfslinie.")
            }
            // 1. Ausnahmeregel: ein weiterer Wert über der Hilfslinie (muss nicht 0,2 °C höher sein)
            guard let v4 = v(4) else { return .pending(higherDays: [first.day, v2.day, v3.day], drop: nil) }
            guard above(v4) else {
                return .failed("Der 3. Wert liegt weniger als 0,2 °C über der Hilfslinie und der 4. Wert (ZT \(v4.day)) nicht über der Hilfslinie (1. Ausnahmeregel nicht erfüllt).")
            }
            if extra == 0 { return .completed(higherDays: [first.day, v2.day, v3.day, v4.day], drop: nil, rule: .exception1) }
            guard let v5 = v(5) else { return .pending(higherDays: [first.day, v2.day, v3.day, v4.day], drop: nil) }
            if above(v5) { return .completed(higherDays: [first.day, v2.day, v3.day, v4.day, v5.day], drop: nil, rule: .exception1) }
            return .failed("Post-Pill-Zusatzwert an ZT \(v5.day) liegt nicht über der Hilfslinie.")
        }

        // Fall B: genau einer von v2/v3 auf oder unter der Hilfslinie → 2. Ausnahmeregel
        if above(v2) != above(v3) {
            let drop = above(v2) ? v3 : v2
            let kept = above(v2) ? v2 : v3
            guard let v4 = v(4) else { return .pending(higherDays: [first.day, kept.day], drop: drop.day) }
            guard above(v4) else {
                return .failed("Zwei Werte (ZT \(drop.day) und ZT \(v4.day)) liegen auf/unter der Hilfslinie.")
            }
            guard strong(v4) else {
                return .failed("Nach einem Absacker (ZT \(drop.day)) liegt der 3. höhere Wert (ZT \(v4.day)) weniger als 0,2 °C über der Hilfslinie – die Ausnahmeregeln dürfen nicht kombiniert werden.")
            }
            if extra == 0 { return .completed(higherDays: [first.day, kept.day, v4.day], drop: drop.day, rule: .exception2) }
            guard let v5 = v(5) else { return .pending(higherDays: [first.day, kept.day, v4.day], drop: drop.day) }
            if above(v5) { return .completed(higherDays: [first.day, kept.day, v4.day, v5.day], drop: drop.day, rule: .exception2) }
            return .failed("Post-Pill-Zusatzwert an ZT \(v5.day) liegt nicht über der Hilfslinie (nur ein Wert darf auf/unter der Hilfslinie liegen).")
        }

        // Fall C: v2 und v3 auf/unter der Hilfslinie
        return .failed("Der 2. und 3. Wert (ZT \(v2.day), ZT \(v3.day)) liegen auf/unter der Hilfslinie.")
    }

    static func dayList(_ days: [Int]) -> String {
        days.map(String.init).joined(separator: ", ")
    }
}
