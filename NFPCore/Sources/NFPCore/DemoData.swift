import Foundation

/// Erzeugt realistische Beispieldaten für den Demo-Modus.
public enum DemoData {
    struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
        mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(Double(hi - lo + 1) * next()) }
    }

    public static func make(today: LocalDate = .today, cycleCount: Int = 6) -> AppData {
        var data = AppData()
        data.settings.acceptedDisclaimer = true
        data.catalogs[0].priorCycleCount = 3
        data.catalogs[0].priorEarliestFirstHigher = 15
        var rng = RNG(state: 42)

        let lengths = (0..<cycleCount).map { _ in rng.int(26, 31) }
        // Der letzte (laufende) Zyklus hat bisher `currentDay` Tage
        let currentDay = 19
        var start = today.adding(days: -(currentDay - 1) - lengths.dropLast().reduce(0, +))

        for (ci, length) in lengths.enumerated() {
            let isCurrent = ci == lengths.count - 1
            let days = isCurrent ? currentDay : length
            let ovulation = length - 14
            for d in 1...days {
                let date = start.adding(days: d - 1)
                var e = DayEntry(date: date)
                e.isFirstCycleDay = d == 1
                e.measurementTime = TemperatureInput.roundToQuarter(6 * 60 + 30 + rng.int(-20, 20))
                // Temperatur
                let base = d <= ovulation ? rng.range(36.40, 36.60) : rng.range(36.85, 37.05)
                e.temperature = TemperatureInput.round(base)
                if ci == 2 && d == 8 {
                    e.temperature = 36.85
                    e.excluded = true
                    e.disturbances = [.alcohol, .lateNight]
                    e.note = "Geburtstagsfeier"
                }
                // Blutung
                let bleeding: [Bleeding] = [.medium, .heavy, .medium, .light, .spotting]
                if d <= 5 { e.bleeding = bleeding[d - 1] }
                // Zervixschleim
                switch d - ovulation {
                case ...(-8): if d > 5 { e.mucus = MucusObservation(feeling: .dry) }
                case -7, -6: e.mucus = MucusObservation(feeling: .nothing)
                case -5: e.mucus = MucusObservation(feeling: .moist)
                case -4, -3: e.mucus = MucusObservation(feeling: .moist, appearance: [.creamy, .whitish])
                case -2, -1, 0: e.mucus = MucusObservation(feeling: .wet, appearance: [.glassy, .stretchy])
                case 1: e.mucus = MucusObservation(feeling: .moist, appearance: [.sticky])
                case 2: e.mucus = MucusObservation(feeling: .nothing)
                default: e.mucus = MucusObservation(feeling: .dry)
                }
                if d - ovulation == 0 { e.mittelschmerz = .right }
                if d - ovulation == -1 { e.bars["lh"] = BarValue(selections: ["positiv"]) }
                if d - ovulation == 9 { e.breast = .tension }
                if d % 9 == 0 { e.bars["mood"] = BarValue(selections: [DefaultBars.moodOptions[rng.int(0, 10)]]) }
                if d == ovulation + 4 && ci % 2 == 0 { e.intercourse = .unprotected }
                if d == 3 { e.medication = "Ibuprofen 400" }
                data.days[date] = e
            }
            start = start.adding(days: length)
        }
        return data
    }
}
