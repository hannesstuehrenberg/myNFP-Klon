import Foundation

/// Fruchtbarkeitsstatus eines Zyklustages
public enum DayStatus: String, Hashable, Sendable {
    /// Unfruchtbar am Zyklusanfang
    case infertileStart
    /// Fruchtbar
    case fertile
    /// Tag, an dem die Auswertung abgeschlossen wird – ab abends unfruchtbar
    case infertileFromEvening
    /// Unfruchtbar nach dem Eisprung
    case infertileAfterOvulation
    /// Noch nicht ausgewertet (Zukunft)
    case unknown

    public var label: String {
        switch self {
        case .infertileStart: return "unfruchtbar (Zyklusanfang)"
        case .fertile: return "fruchtbar"
        case .infertileFromEvening: return "ab abends unfruchtbar"
        case .infertileAfterOvulation: return "unfruchtbar (nach dem Eisprung)"
        case .unknown: return "noch nicht ausgewertet"
        }
    }

    public var isInfertile: Bool { self == .infertileStart || self == .infertileAfterOvulation }
}

public enum StartRule: String, Hashable, Sendable {
    case none = "keine"
    case fiveDay = "5-Tage-Regel"
    case minus8 = "Minus-8-Regel"
    case minus20 = "Minus-20-Regel"
    case manual = "manuell"
}

public struct StartPhaseResult: Hashable, Sendable {
    /// Letzter unfruchtbarer Zyklustag am Anfang (0 = keiner)
    public var infertileUntilDay: Int = 0
    /// Ohne Symptome berechnete Grenze nach Regel
    public var ruleLimit: Int = 0
    public var rule: StartRule = .none
    /// Tag, an dem ein Symptom die unfruchtbare Zeit beendet hat
    public var endedBySymptomDay: Int?
    public var log: [ProtocolEntry] = []
}

public struct PeriodForecast: Hashable, Sendable {
    /// Frühester und spätester erwarteter Beginn der nächsten Periode
    public var earliest: LocalDate
    public var latest: LocalDate
    /// Grundlage der Prognose (Anzahl berücksichtigter Hochlagen)
    public var basedOnHighPhases: Int
}

public struct PregnancyInfo: Hashable, Sendable {
    /// Aktueller Hochlagentag (1.hM = Tag 1)
    public var highPhaseDay: Int
    /// Voraussichtlicher Entbindungstermin (1.hM + 266 Tage)
    public var dueDate: LocalDate
    /// Bezugstag für SSW 0+0 (1.hM − 14 Tage)
    public var referenceDate: LocalDate

    public func week(on date: LocalDate) -> (weeks: Int, days: Int) {
        let k = max(0, referenceDate.days(until: date))
        return (k / 7, k % 7)
    }

    public func weekLabel(on date: LocalDate) -> String {
        let w = week(on: date)
        return "SSW \(w.weeks)+\(w.days)"
    }
}

public struct CycleEvaluation: Hashable, Sendable {
    public var cycleStart: LocalDate
    public var catalogID: UUID
    public var isManual: Bool
    public var isLax: Bool
    public var isPostPill: Bool
    public var doubleCheck: DoubleCheckSymptom

    public var temperature: TemperatureResult
    public var mucus: PeakResult
    public var cervix: PeakResult
    public var startPhase: StartPhaseResult

    /// Ab dem Abend dieses Tages unfruchtbar (Doppelkontrolle abgeschlossen)
    public var infertileFromEveningOfDay: Int?
    /// Status je Zyklustag (Index 0 = ZT 1)
    public var dayStatuses: [DayStatus]

    /// Länge der Hochlage (1.hM bis Zyklusende) bei abgeschlossenen Zyklen
    public var highPhaseLength: Int?
    /// War die 1.hM dieses Zyklus die bisher früheste im Katalog?
    public var isEarliestFirstHigher: Bool
    /// Früheste 1.hM im Katalog bis einschließlich dieses Zyklus
    public var earliestFirstHigherSoFar: Int?
    public var cyclesWithFirstHigherBefore: Int

    public var periodForecast: PeriodForecast?
    public var pregnancy: PregnancyInfo?

    /// Vollständiges Auswertungsprotokoll
    public var log: [ProtocolEntry]
    public var hints: [String]

    public var firstHigherDay: Int? { temperature.firstHigherDay }

    public func status(day: Int) -> DayStatus {
        guard day >= 1, day <= dayStatuses.count else { return .unknown }
        return dayStatuses[day - 1]
    }

    /// Ab wann die unfruchtbare Phase nach dem Eisprung gilt, als Tag
    public var isOvulationConfirmed: Bool { infertileFromEveningOfDay != nil }
}

public struct EvaluationOptions: Sendable {
    public var lax: Bool
    public var subdifferentiation: Bool
    public var cycleStartByCervix: Bool
    public var doubleCheck: DoubleCheckSymptom

    public init(lax: Bool = false, subdifferentiation: Bool = false, cycleStartByCervix: Bool = false,
                doubleCheck: DoubleCheckSymptom = .mucus) {
        self.lax = lax
        self.subdifferentiation = subdifferentiation
        self.cycleStartByCervix = cycleStartByCervix
        self.doubleCheck = doubleCheck
    }

    public init(settings: AppSettings) {
        self.init(lax: settings.effectiveLax,
                  subdifferentiation: settings.effectiveSubdifferentiation,
                  cycleStartByCervix: settings.effectiveCycleStartByCervix,
                  doubleCheck: settings.doubleCheck)
    }
}

public enum CycleEvaluator {
    /// Anzahl Zyklen mit 1.hM, ab der die Minus-8-Regel auch verlängern darf
    public static let cyclesForMinus8Extension = 12
    /// Ab diesem Hochlagentag gilt eine Schwangerschaft als wahrscheinlich (lila Balken)
    public static let pregnancyHighPhaseDay = 19

    /// Wertet alle Zyklen aus. Kataloge werden getrennt betrachtet.
    public static func evaluateAll(cycles: [Cycle], data: AppData, today: LocalDate = .today) -> [LocalDate: CycleEvaluation] {
        let options = EvaluationOptions(settings: data.settings)
        var results: [LocalDate: CycleEvaluation] = [:]

        // Historie je Katalog
        struct History {
            var firstHigherDays: [Int] = []
            var highPhaseLengths: [Int] = []
            var previousHadFirstHigher: Bool? = nil
            var confirmedFirstHigherSeen = false
        }
        var histories: [UUID: History] = [:]

        for cycle in cycles {
            let catalog = data.catalog(id: cycle.meta.catalogID)
            var h = histories[catalog.id] ?? History()

            let ctx = CatalogContext(
                catalog: catalog,
                previousFirstHigherDays: h.firstHigherDays,
                previousHighPhaseLengths: h.highPhaseLengths,
                previousCycleHadFirstHigher: h.previousHadFirstHigher,
                postPillActive: catalog.postPill && !h.confirmedFirstHigherSeen
            )
            let ev = evaluate(cycle: cycle, context: ctx, options: options, today: today)
            results[cycle.startDate] = ev

            let confirmed = ev.temperature.status == .completed || (ev.isManual && ev.temperature.firstHigherDay != nil)
            if confirmed, let fhm = ev.temperature.firstHigherDay {
                h.firstHigherDays.append(fhm)
                h.confirmedFirstHigherSeen = true
                if cycle.isCompleted { h.highPhaseLengths.append(cycle.length - fhm + 1) }
            }
            h.previousHadFirstHigher = confirmed && ev.temperature.firstHigherDay != nil
            histories[catalog.id] = h
        }
        return results
    }

    public struct CatalogContext: Sendable {
        public var catalog: Catalog
        /// 1.hM-Tage der vorherigen Zyklen dieses Katalogs (chronologisch)
        public var previousFirstHigherDays: [Int]
        public var previousHighPhaseLengths: [Int]
        /// nil = erster Zyklus im Katalog
        public var previousCycleHadFirstHigher: Bool?
        public var postPillActive: Bool

        public init(catalog: Catalog, previousFirstHigherDays: [Int] = [], previousHighPhaseLengths: [Int] = [],
                    previousCycleHadFirstHigher: Bool? = nil, postPillActive: Bool = false) {
            self.catalog = catalog
            self.previousFirstHigherDays = previousFirstHigherDays
            self.previousHighPhaseLengths = previousHighPhaseLengths
            self.previousCycleHadFirstHigher = previousCycleHadFirstHigher
            self.postPillActive = postPillActive
        }

        var cyclesWithFirstHigher: Int { catalog.priorCycleCount + previousFirstHigherDays.count }

        var earliestFirstHigher: Int? {
            let all = previousFirstHigherDays + (catalog.priorEarliestFirstHigher.map { [$0] } ?? [])
            return all.min()
        }
    }

    // MARK: - Einzelner Zyklus

    public static func evaluate(cycle: Cycle, context ctx: CatalogContext, options: EvaluationOptions,
                                today: LocalDate = .today) -> CycleEvaluation {
        let lastObservedDay: Int = cycle.isCompleted ? cycle.length : max(0, min(cycle.length, cycle.cycleDay(of: today)))
        var log: [ProtocolEntry] = []
        var hints: [String] = []
        let isManual = cycle.meta.useManualEvaluation

        log.append(.info("Katalog „\(ctx.catalog.name)“: \(ctx.cyclesWithFirstHigher) Zyklen mit 1. höherer Messung vor diesem Zyklus" +
                         (ctx.catalog.priorCycleCount > 0 ? " (davon \(ctx.catalog.priorCycleCount) aus früheren Aufzeichnungen)." : ".")))
        if let e = ctx.earliestFirstHigher { log.append(.info("Bisher früheste 1. höhere Messung: ZT \(e).")) }
        if options.lax { log.append(.info("Laxe Auswertung aktiv: Ein Tag ohne Schleim-/Muttermund-Eintrag zählt wie die schlechteste Qualität.")) }
        if ctx.postPillActive { log.append(.info("Post-Pill-Regeln aktiv (noch keine bestätigte 1. höhere Messung seit Absetzen hormoneller Verhütung).")) }

        var temperature: TemperatureResult
        var mucus = PeakResult()
        var cervix = PeakResult()
        var start = StartPhaseResult()
        var infertileFrom: Int?

        if isManual {
            log.append(.info("Dieser Zyklus wird manuell ausgewertet."))
            let m = cycle.meta.manual
            temperature = TemperatureResult()
            temperature.coverline = m.coverline
            temperature.firstHigherDay = m.firstHigherDay
            temperature.rule = .manual
            temperature.status = m.firstHigherDay != nil ? .completed : .none
            if let f = m.firstHigherDay { temperature.higherDays = [f, f + 1, f + 2].filter { $0 <= cycle.length } }
            if let p = m.mucusPeakDay {
                mucus.status = .completed; mucus.peakDay = p; mucus.completionDay = p + 3
                mucus.afterPeakDays = [p + 1, p + 2, p + 3]
            }
            if let p = m.cervixPeakDay {
                cervix.status = .completed; cervix.peakDay = p; cervix.completionDay = p + 3
                cervix.afterPeakDays = [p + 1, p + 2, p + 3]
            }
            start.infertileUntilDay = m.infertileStartUntilDay ?? 0
            start.ruleLimit = start.infertileUntilDay
            start.rule = .manual
            infertileFrom = m.infertileFromEveningOfDay
            if let f = m.firstHigherDay { log.append(.rule("1. höhere Messung (manuell): ZT \(f).")) }
            if let c = m.coverline { log.append(.rule("Hilfslinie (manuell): \(TemperatureInput.format(c)) °C.")) }
            if let p = m.mucusPeakDay { log.append(.rule("Schleim-Höhepunkt (manuell): ZT \(p).")) }
            if let p = m.cervixPeakDay { log.append(.rule("Muttermund-Höhepunkt (manuell): ZT \(p).")) }
            log.append(.rule("Unfruchtbar am Zyklusanfang (manuell): \(start.infertileUntilDay > 0 ? "bis ZT \(start.infertileUntilDay)" : "keine Tage")."))
            if let i = infertileFrom { log.append(.result("Unfruchtbar ab dem Abend von ZT \(i) (manuell).")) }
        } else {
            // 1) Temperatur
            temperature = TemperatureEvaluator.evaluate(cycle: cycle, postPill: ctx.postPillActive, lastObservedDay: lastObservedDay)
            log.append(contentsOf: temperature.log)

            // 2) Schleim und Muttermund
            let tc = temperature.status == .completed ? temperature.completionDay : nil
            mucus = PeakEvaluator.mucus(cycle: cycle, lastObservedDay: lastObservedDay, lax: options.lax,
                                        subdifferentiation: options.subdifferentiation)
                .evaluate(temperatureCompletionDay: tc)
            cervix = PeakEvaluator.cervix(cycle: cycle, lastObservedDay: lastObservedDay, lax: options.lax)
                .evaluate(temperatureCompletionDay: tc)
            let primary = options.doubleCheck == .mucus ? mucus : cervix
            log.append(contentsOf: primary.log)
            if options.doubleCheck == .mucus, !cervix.log.isEmpty, cycle.entries.contains(where: { $0?.cervix != nil }) {
                log.append(contentsOf: cervix.log.filter { $0.kind != .info })
            }

            // 3) Doppelkontrolle
            if temperature.status == .completed, primary.status == .completed,
               let t = temperature.completionDay, let p = primary.completionDay {
                infertileFrom = max(t, p)
                let which = t >= p ? "Temperaturauswertung" : "\(options.doubleCheck.label)auswertung"
                log.append(.result("Doppelkontrolle: Unfruchtbar ab dem Abend von ZT \(infertileFrom!) (zuletzt abgeschlossen: \(which))."))
            } else {
                var missing: [String] = []
                if temperature.status != .completed { missing.append("Temperatur") }
                if primary.status != .completed { missing.append(options.doubleCheck.label) }
                log.append(.info("Unfruchtbare Phase nach dem Eisprung noch nicht bestimmt – offen: \(missing.joined(separator: " und "))."))
            }

            // Hinweis zeitlicher Zusammenhang Höhepunkt ↔ 1.hM
            if let fhm = temperature.firstHigherDay, let peak = primary.peakDay, primary.status == .completed {
                if peak < fhm - 5 {
                    hints.append("Der Höhepunkt (ZT \(peak)) liegt mehr als 5 Tage vor der 1. höheren Messung (ZT \(fhm)). Bitte Auswertung prüfen.")
                } else if peak > fhm + 3 {
                    hints.append("Der Höhepunkt (ZT \(peak)) liegt mehr als 3 Tage nach der 1. höheren Messung (ZT \(fhm)). Bitte Auswertung prüfen.")
                }
            }

            // 4) Zyklusanfang
            start = evaluateStart(cycle: cycle, context: ctx, options: options, lastObservedDay: lastObservedDay)
            log.append(contentsOf: start.log)
        }

        // 5) Tagesstatus
        var statuses: [DayStatus] = []
        statuses.reserveCapacity(cycle.length)
        for day in 1...max(1, cycle.length) {
            let s: DayStatus
            if let i = infertileFrom, day > i {
                s = .infertileAfterOvulation
            } else if let i = infertileFrom, day == i {
                s = .infertileFromEvening
            } else if day <= start.infertileUntilDay {
                s = .infertileStart
            } else if day > lastObservedDay && !cycle.isCompleted {
                s = .unknown
            } else {
                s = .fertile
            }
            statuses.append(s)
        }

        // 6) Hochlage, früheste 1.hM
        var highPhaseLength: Int?
        var isEarliest = false
        var earliestSoFar = ctx.earliestFirstHigher
        if let fhm = temperature.firstHigherDay, temperature.status == .completed {
            if cycle.isCompleted { highPhaseLength = cycle.length - fhm + 1 }
            if let e = earliestSoFar {
                isEarliest = fhm <= e
                earliestSoFar = min(e, fhm)
            } else {
                isEarliest = true
                earliestSoFar = fhm
            }
        }

        // 7) Periodenprognose (roter Balken) und Schwangerschaft (lila Balken)
        var forecast: PeriodForecast?
        var pregnancy: PregnancyInfo?
        if !cycle.isCompleted, let fhm = temperature.firstHigherDay {
            forecast = periodForecast(cycle: cycle, firstHigherDay: fhm, context: ctx)
            if temperature.status == .completed {
                let fhmDate = cycle.date(ofDay: fhm)
                let highDay = fhmDate.days(until: today) + 1
                if highDay >= pregnancyHighPhaseDay {
                    pregnancy = PregnancyInfo(highPhaseDay: highDay, dueDate: fhmDate.adding(days: 266),
                                              referenceDate: fhmDate.adding(days: -14))
                    log.append(.info("Hochlagentag \(highDay): Eine Schwangerschaft ist wahrscheinlich. Voraussichtlicher Entbindungstermin: \(fhmDate.adding(days: 266).german)."))
                }
            }
        }

        if !hints.isEmpty { log.append(contentsOf: hints.map { .warning($0) }) }

        return CycleEvaluation(
            cycleStart: cycle.startDate,
            catalogID: ctx.catalog.id,
            isManual: isManual,
            isLax: options.lax,
            isPostPill: ctx.postPillActive,
            doubleCheck: options.doubleCheck,
            temperature: temperature,
            mucus: mucus,
            cervix: cervix,
            startPhase: start,
            infertileFromEveningOfDay: infertileFrom,
            dayStatuses: statuses,
            highPhaseLength: highPhaseLength,
            isEarliestFirstHigher: isEarliest,
            earliestFirstHigherSoFar: earliestSoFar,
            cyclesWithFirstHigherBefore: ctx.cyclesWithFirstHigher,
            periodForecast: forecast,
            pregnancy: pregnancy,
            log: log,
            hints: hints
        )
    }

    // MARK: - Unfruchtbarkeit am Zyklusanfang

    static func evaluateStart(cycle: Cycle, context ctx: CatalogContext, options: EvaluationOptions,
                              lastObservedDay: Int) -> StartPhaseResult {
        var r = StartPhaseResult()

        if ctx.postPillActive {
            r.log.append(.rule("Zyklusanfang: Post-Pill – Fruchtbarkeit ab dem 1. Zyklustag."))
            return r
        }
        // Vorbedingung: 1.hM im Vorzyklus
        let preconditionMet: Bool
        if let prev = ctx.previousCycleHadFirstHigher {
            preconditionMet = prev
        } else {
            preconditionMet = ctx.catalog.priorCycleCount > 0
        }
        guard preconditionMet else {
            if ctx.previousCycleHadFirstHigher == nil {
                r.log.append(.rule("Zyklusanfang: Erster Zyklus im Katalog ohne frühere Aufzeichnungen – es ist nicht bekannt, ob im Vorzyklus ein Eisprung stattfand. Fruchtbarkeit ab dem 1. Zyklustag."))
            } else {
                r.log.append(.rule("Zyklusanfang: Im Vorzyklus wurde keine 1. höhere Messung festgestellt. Fruchtbarkeit ab dem 1. Zyklustag."))
            }
            return r
        }

        var limit: Int
        var rule: StartRule
        let earliest = ctx.earliestFirstHigher
        if ctx.cyclesWithFirstHigher >= cyclesForMinus8Extension, let e = earliest {
            limit = e - 8
            rule = .minus8
            r.log.append(.rule("Minus-8-Regel: \(ctx.cyclesWithFirstHigher) Zyklen mit 1.hM, früheste 1.hM an ZT \(e) → unfruchtbar bis ZT \(e - 8)."))
        } else {
            if let shortest = ctx.catalog.shortestCycleForMinus20, shortest - 20 > 0 {
                limit = shortest - 20
                rule = .minus20
                r.log.append(.rule("Minus-20-Regel: kürzester Zyklus \(shortest) Tage → unfruchtbar bis ZT \(limit)."))
            } else {
                limit = 5
                rule = .fiveDay
                r.log.append(.rule("5-Tage-Regel: Die ersten 5 Zyklustage gelten als unfruchtbar."))
            }
            if let e = earliest, e - 8 < limit {
                limit = e - 8
                rule = .minus8
                r.log.append(.rule("Minus-8-Regel verkürzt: früheste 1.hM an ZT \(e) → unfruchtbar nur bis ZT \(max(0, e - 8))."))
            }
            if ctx.cyclesWithFirstHigher < cyclesForMinus8Extension {
                r.log.append(.info("Weniger als \(cyclesForMinus8Extension) Zyklen mit 1.hM: höchstens \(rule == .minus20 ? "Minus-20-Regel" : "5 Tage")."))
            }
        }
        limit = max(0, min(limit, cycle.length))
        r.ruleLimit = limit
        r.rule = limit > 0 ? rule : .none
        r.infertileUntilDay = limit
        guard limit > 0 else { return r }

        // Symptome beenden die unfruchtbare Zeit sofort
        for day in 1...limit {
            guard day <= lastObservedDay else { break }
            let e = cycle.entry(day: day)
            if options.cycleStartByCervix {
                if let c = e?.cervix, c.isComplete, !c.isClosedAndHard {
                    r.infertileUntilDay = day - 1
                    r.endedBySymptomDay = day
                    r.log.append(.rule("Muttermund an ZT \(day) verändert (geöffnet bzw. weich) → ab sofort fruchtbar."))
                    break
                }
            } else if let s = e?.mucus?.symbol, s >= .f {
                r.infertileUntilDay = day - 1
                r.endedBySymptomDay = day
                r.log.append(.rule("Zervixschleim „\(s.label)“ an ZT \(day) → ab sofort fruchtbar (Schleim der Kategorie f, S oder S+)."))
                break
            }
            // Strenge Auswertung: An vergangenen Tagen ohne Blutung muss ein Eintrag vorhanden sein
            // (heute darf noch offen sein).
            if !options.lax && day < lastObservedDay {
                let hasObservation = options.cycleStartByCervix ? (e?.cervix?.isComplete ?? false) : (e?.mucus?.symbol != nil)
                let bleedingHides = e?.bleeding != nil
                if !hasObservation && !bleedingHides {
                    r.infertileUntilDay = day - 1
                    r.endedBySymptomDay = day
                    r.log.append(.warning("An ZT \(day) fehlt ein \(options.cycleStartByCervix ? "Muttermund" : "Schleim")-Eintrag (keine Blutung) → ab diesem Tag fruchtbar."))
                    break
                }
            }
        }
        if r.infertileUntilDay > 0 {
            r.log.append(.result("Unfruchtbar am Zyklusanfang bis einschließlich ZT \(r.infertileUntilDay)."))
        } else {
            r.log.append(.result("Keine unfruchtbaren Tage am Zyklusanfang."))
        }
        return r
    }

    // MARK: - Prognose

    static func periodForecast(cycle: Cycle, firstHigherDay fhm: Int, context ctx: CatalogContext) -> PeriodForecast {
        // Nur die letzten 20 Hochlagen des aktuellen Katalogs
        let lengths = Array(ctx.previousHighPhaseLengths.suffix(20))
        let lo: Int, hi: Int
        if lengths.count >= 3 {
            let sorted = lengths.sorted()
            let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
            let variance = lengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(lengths.count - 1)
            let sd = max(1.0, sqrt(variance))
            lo = max(sorted.first!, Int((mean - sd).rounded(.down)))
            hi = min(sorted.last!, Int((mean + sd).rounded(.up)))
        } else if let mn = lengths.min(), let mx = lengths.max() {
            lo = min(mn, 12); hi = max(mx, 16)
        } else {
            // Typische Hochlage 12–16 Tage
            lo = 12; hi = 16
        }
        let shift = ctx.catalog.periodForecastShift
        let fhmDate = cycle.date(ofDay: fhm)
        return PeriodForecast(earliest: fhmDate.adding(days: lo + shift),
                              latest: fhmDate.adding(days: max(lo, hi) + shift),
                              basedOnHighPhases: lengths.count)
    }
}
