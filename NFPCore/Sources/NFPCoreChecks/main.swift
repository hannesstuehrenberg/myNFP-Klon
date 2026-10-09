import Foundation
import NFPCore

// Leichtgewichtige Testsuite, die ohne Xcode/XCTest läuft: `swift run NFPCoreChecks`

var failures = 0
var passed = 0
var currentGroup = ""

func group(_ name: String, _ body: () throws -> Void) {
    currentGroup = name
    do { try body() } catch {
        failures += 1
        print("✗ [\(name)] unerwarteter Fehler: \(error)")
    }
}

func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if cond() { passed += 1 } else {
        failures += 1
        print("✗ [\(currentGroup)] \(msg) (Zeile \(line))")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String, line: Int = #line) {
    check(a == b, "\(msg): erwartet \(b), erhalten \(a)", line: line)
}

// MARK: Hilfen

/// Vergleich ohne Zeitstempel (ISO-8601 speichert nur Millisekunden)
func normalized(_ d: AppData) -> AppData { var x = d; x.modifiedAt = Date(timeIntervalSince1970: 0); return x }

let start = LocalDate(year: 2026, month: 1, day: 1)

/// Baut einen Zyklus aus Temperaturen (nil = keine Messung) und optionalen Schleimsymbolen.
func makeCycle(temps: [Double?], mucus: [MucusSymbol?] = [], bleedingDays: Int = 0, completed: Bool = true,
               startDate: LocalDate = start, excluded: Set<Int> = []) -> Cycle {
    let n = max(temps.count, mucus.count)
    var entries: [DayEntry?] = []
    for i in 0..<n {
        var e = DayEntry(date: startDate.adding(days: i))
        e.isFirstCycleDay = i == 0
        if i < temps.count { e.temperature = temps[i] }
        if i < mucus.count, let m = mucus[i] { e.mucus = .symbol(m) }
        if i < bleedingDays { e.bleeding = .medium }
        if excluded.contains(i + 1) { e.excluded = true }
        entries.append(e)
    }
    return Cycle(startDate: startDate, endDate: startDate.adding(days: n - 1), isCompleted: completed,
                 meta: CycleMeta(), entries: entries)
}

let lows: [Double?] = [36.40, 36.50, 36.40, 36.45, 36.50, 36.40]

// MARK: - Tests

group("LocalDate") {
    let d = LocalDate(year: 2026, month: 10, day: 9)
    eq(d.isoString, "2026-10-09", "ISO")
    eq(LocalDate(isoString: "2026-10-09"), d, "Parse")
    eq(d.isoWeekday, 5, "Freitag")
    eq(d.adding(days: 23).isoString, "2026-11-01", "Addition")
    eq(LocalDate(year: 2024, month: 2, day: 28).adding(days: 1).day, 29, "Schaltjahr")
    eq(LocalDate(year: 2026, month: 1, day: 31).adding(months: 1).isoString, "2026-02-28", "Monatsaddition")
    eq(LocalDate(year: 1970, month: 1, day: 1).dayNumber, 0, "Epoche")
    let roundtrip = (try? JSONDecoder().decode(LocalDate.self, from: JSONEncoder().encode(d))) ?? start
    eq(roundtrip, d, "Codable")
}

group("Temperatur-Eingabe") {
    eq(TemperatureInput.round(36.23), 36.25, "36,23 → 36,25")
    eq(TemperatureInput.round(37.02), 37.00, "37,02 → 37,00")
    eq(TemperatureInput.round(36.67), 36.65, "36,67 → 36,65")
    eq(TemperatureInput.round(36.68), 36.70, "36,68 → 36,70")
    eq(TemperatureInput.parse("36,65"), 36.65, "Komma")
    eq(TemperatureInput.parse("3665"), 36.65, "4 Ziffern")
    eq(TemperatureInput.parse("37"), 37.00, "37 = 37,00")
    eq(TemperatureInput.parse("370"), 37.00, "370 = 37,00")
    check(TemperatureInput.parse("12") == nil, "unplausibel")
    eq(TemperatureInput.format(36.5), "36,50", "Format")
    eq(TemperatureInput.roundToQuarter(8 * 60 + 23), 8 * 60 + 30, "Viertelstunde")
}

group("Schnelleingabe") {
    var r = QuickEntryParser.parse("3667 ggv bs")
    eq(r.temperature, 36.65, "Temperatur")
    eq(r.intercourse, .protected, "ggv")
    eq(r.breast, .pain, "bs")
    eq(QuickEntryParser.parse("67").temperature, 36.65, "Nachkommastellen 67")
    eq(QuickEntryParser.parse("37").temperature, 36.35, "Schnelleingabe 37 = 36,35")
    eq(QuickEntryParser.parse("370").temperature, 37.00, "370")
    eq(QuickEntryParser.parse("355").temperature, 35.50, "355 ist Temperatur")
    eq(QuickEntryParser.parse("823").time, 8 * 60 + 30, "823 → 08:30")
    eq(QuickEntryParser.parse("6:20").time, 6 * 60 + 15, "6:20 → 06:15")
    eq(QuickEntryParser.parse("sp").mucus?.symbol, .sPlus, "sp")
    eq(QuickEntryParser.parse("s+").mucus?.symbol, .sPlus, "s+")
    eq(QuickEntryParser.parse("o").mucus?.symbol, .nothing, "o")
    check(QuickEntryParser.parse("(s)").mucus?.reduced == true, "(s)")
    eq(QuickEntryParser.parse("xxx").bleeding, .medium, "xxx")
    eq(QuickEntryParser.parse("****").bleeding, .heavy, "****")
    eq(QuickEntryParser.parse("x").bleeding, .spotting, "x")
    eq(QuickEntryParser.parse("l").mittelschmerz, .left, "l")
    r = QuickEntryParser.parse("t 3650 # Kopfweh heute")
    eq(r.note, "Kopfweh heute", "Notiz")
    eq(r.mucus?.symbol, .t, "t")
    eq(QuickEntryParser.parse("foo 3650").unrecognized, ["foo"], "unbekannt")
}

group("Zervixschleim-Symbol") {
    eq(MucusObservation(feeling: .dry).symbol, .t, "trocken")
    eq(MucusObservation(feeling: .nothing).symbol, .nothing, "nichts")
    eq(MucusObservation(feeling: .moist).symbol, .f, "feucht")
    eq(MucusObservation(feeling: .moist, appearance: [.creamy]).symbol, .s, "cremig")
    eq(MucusObservation(feeling: .nothing, appearance: [.creamy, .stretchy]).symbol, .sPlus, "fruchtbarste zählt")
    eq(MucusObservation(feeling: .wet).symbol, .sPlus, "nass")
    eq(MucusObservation(feeling: .moist, appearance: [.milky]).symbol, .s, "milchig")
    check(MucusObservation().symbol == nil, "leer")
}

group("Temperatur: Grundregel") {
    let c = makeCycle(temps: lows + [36.60, 36.65, 36.70, 36.75])
    let r = TemperatureEvaluator.evaluate(cycle: c, postPill: false)
    eq(r.status, .completed, "abgeschlossen")
    eq(r.coverline, 36.50, "Hilfslinie")
    eq(r.firstHigherDay, 7, "1.hM")
    eq(r.completionDay, 9, "Abschluss am 3. höheren Wert")
    eq(r.rule, .regular, "Grundregel")
    eq(r.lowDays, [1, 2, 3, 4, 5, 6], "6 niedrige")
}

group("Temperatur: 1. Ausnahmeregel") {
    let c = makeCycle(temps: lows + [36.60, 36.60, 36.65, 36.55])
    let r = TemperatureEvaluator.evaluate(cycle: c, postPill: false)
    eq(r.status, .completed, "abgeschlossen")
    eq(r.rule, .exception1, "Ausnahme 1")
    eq(r.completionDay, 10, "4. Wert")
    // 4. Wert auf der Hilfslinie → nicht erfüllt
    let c2 = makeCycle(temps: lows + [36.60, 36.60, 36.65, 36.50])
    let r2 = TemperatureEvaluator.evaluate(cycle: c2, postPill: false)
    check(r2.status != .completed, "4. Wert auf Hilfslinie → nicht abgeschlossen")
}

group("Temperatur: 2. Ausnahmeregel") {
    let c = makeCycle(temps: lows + [36.60, 36.50, 36.65, 36.70])
    let r = TemperatureEvaluator.evaluate(cycle: c, postPill: false)
    eq(r.status, .completed, "abgeschlossen")
    eq(r.rule, .exception2, "Ausnahme 2")
    eq(r.ignoredDropDay, 8, "Absacker")
    eq(r.completionDay, 10, "Abschluss")
    // Kombination verboten: nach Absacker nur 0,1 über Hilfslinie
    let c2 = makeCycle(temps: lows + [36.60, 36.50, 36.60, 36.60])
    let r2 = TemperatureEvaluator.evaluate(cycle: c2, postPill: false)
    check(r2.status != .completed, "Ausnahmeregeln nicht kombinierbar")
    check(r2.log.contains { $0.text.contains("nicht kombiniert") }, "Protokollhinweis Kombination")
}

group("Temperatur: Lücken & Ausklammern") {
    // Lücke in der Tieflage und ein ausgeklammerter hoher Wert
    var temps = lows
    temps.insert(nil, at: 3)
    temps.insert(36.90, at: 2) // ZT 3 gestört
    let c = makeCycle(temps: temps + [36.60, 36.65, 36.70], excluded: [3])
    let r = TemperatureEvaluator.evaluate(cycle: c, postPill: false)
    eq(r.status, .completed, "abgeschlossen trotz Lücke")
    eq(r.coverline, 36.50, "ausgeklammerter Wert ignoriert")
    eq(r.firstHigherDay, 9, "1.hM")
}

group("Temperatur: Post-Pill & offen") {
    let c = makeCycle(temps: lows + [36.60, 36.65, 36.70])
    let r = TemperatureEvaluator.evaluate(cycle: c, postPill: true)
    eq(r.status, .pending, "Post-Pill wartet auf 4. Wert")
    let c2 = makeCycle(temps: lows + [36.60, 36.65, 36.70, 36.55])
    let r2 = TemperatureEvaluator.evaluate(cycle: c2, postPill: true)
    eq(r2.status, .completed, "Post-Pill abgeschlossen")
    eq(r2.completionDay, 10, "4. Anstiegstag")
    let c3 = makeCycle(temps: lows + [36.60, 36.65])
    eq(TemperatureEvaluator.evaluate(cycle: c3, postPill: false).status, .pending, "noch offen")
}

group("Doppelkontrolle & Zyklusanfang") {
    // ZT 1–4 Blutung, Schleim-Höhepunkt ZT 11, 1.hM ZT 13
    let temps: [Double?] = [36.4, 36.45, 36.4, 36.5, 36.45, 36.4, 36.45, 36.5, 36.4, 36.45, 36.5, 36.45,
                            36.65, 36.70, 36.75, 36.8, 36.8, 36.85]
    let mucus: [MucusSymbol?] = [nil, nil, nil, nil, .t, .t, .nothing, .f, .s, .sPlus, .sPlus, .s, .f, .t, .t, .t, .t, .t]
    let c = makeCycle(temps: temps, mucus: mucus, bleedingDays: 4)
    let cat = Catalog(name: "Test", priorCycleCount: 5)
    let ctx = CycleEvaluator.CatalogContext(catalog: cat, previousFirstHigherDays: [14, 15], previousCycleHadFirstHigher: true)
    let ev = CycleEvaluator.evaluate(cycle: c, context: ctx, options: EvaluationOptions(), today: c.endDate)
    eq(ev.temperature.completionDay, 15, "Temperatur abgeschlossen ZT 15")
    eq(ev.mucus.peakDay, 11, "Höhepunkt ZT 11")
    eq(ev.mucus.completionDay, 14, "Schleim abgeschlossen ZT 14")
    eq(ev.infertileFromEveningOfDay, 15, "Doppelkontrolle: später abgeschlossene Auswertung zählt")
    eq(ev.status(day: 15), .infertileFromEvening, "ZT 15 ab abends")
    eq(ev.status(day: 16), .infertileAfterOvulation, "ZT 16 unfruchtbar")
    eq(ev.startPhase.rule, .fiveDay, "5-Tage-Regel")
    eq(ev.startPhase.infertileUntilDay, 5, "unfruchtbar bis ZT 5")
    eq(ev.status(day: 5), .infertileStart, "ZT 5 unfruchtbar")
    eq(ev.status(day: 6), .fertile, "ZT 6 fruchtbar")

    // Minus-8 verkürzt: früheste 1.hM ZT 12 → bis ZT 4
    let ctx2 = CycleEvaluator.CatalogContext(catalog: cat, previousFirstHigherDays: [12, 15], previousCycleHadFirstHigher: true)
    let ev2 = CycleEvaluator.evaluate(cycle: c, context: ctx2, options: EvaluationOptions(), today: c.endDate)
    eq(ev2.startPhase.infertileUntilDay, 4, "Minus-8 verkürzt")
    eq(ev2.startPhase.rule, .minus8, "Regel Minus-8")

    // Ab 12 Zyklen: Minus-8 verlängert (früheste 1.hM 16 → bis ZT 8), aber Schleim f an ZT 8 beendet → bis ZT 7
    let ctx3 = CycleEvaluator.CatalogContext(catalog: Catalog(name: "x", priorCycleCount: 10),
                                             previousFirstHigherDays: [16, 17], previousCycleHadFirstHigher: true)
    let ev3 = CycleEvaluator.evaluate(cycle: c, context: ctx3, options: EvaluationOptions(), today: c.endDate)
    eq(ev3.startPhase.ruleLimit, 8, "Minus-8 verlängert")
    eq(ev3.startPhase.infertileUntilDay, 7, "Schleim f beendet")
    eq(ev3.startPhase.endedBySymptomDay, 8, "Symptomtag")

    // Kein Eisprung im Vorzyklus
    let ctx4 = CycleEvaluator.CatalogContext(catalog: cat, previousFirstHigherDays: [14], previousCycleHadFirstHigher: false)
    eq(CycleEvaluator.evaluate(cycle: c, context: ctx4, options: EvaluationOptions(), today: c.endDate).startPhase.infertileUntilDay, 0,
       "ohne 1.hM im Vorzyklus fruchtbar ab ZT 1")

    // Erster Zyklus ohne frühere Aufzeichnungen
    let ctx5 = CycleEvaluator.CatalogContext(catalog: Catalog(name: "neu"))
    eq(CycleEvaluator.evaluate(cycle: c, context: ctx5, options: EvaluationOptions(), today: c.endDate).startPhase.infertileUntilDay, 0,
       "erster Zyklus fruchtbar ab ZT 1")

    // Post-Pill
    let ctx6 = CycleEvaluator.CatalogContext(catalog: Catalog(name: "pp", postPill: true), postPillActive: true)
    let ev6 = CycleEvaluator.evaluate(cycle: c, context: ctx6, options: EvaluationOptions(), today: c.endDate)
    eq(ev6.startPhase.infertileUntilDay, 0, "Post-Pill fruchtbar ab ZT 1")
    eq(ev6.temperature.completionDay, 16, "Post-Pill: zusätzlicher Wert")

    // Minus-20
    let ctx7 = CycleEvaluator.CatalogContext(catalog: Catalog(name: "m20", priorCycleCount: 2, shortestCycleForMinus20: 27),
                                             previousCycleHadFirstHigher: nil)
    let ev7 = CycleEvaluator.evaluate(cycle: c, context: ctx7, options: EvaluationOptions(), today: c.endDate)
    eq(ev7.startPhase.rule, .minus20, "Minus-20")
    eq(ev7.startPhase.infertileUntilDay, 7, "Minus-20: bis ZT 7")
}

group("Schleim: erneuter Anstieg & strenge Auswertung") {
    // Höhepunkt ZT 9, aber an ZT 14 erneut S+ vor Abschluss der Temperatur (ZT 16) → neuer Höhepunkt ZT 14
    let temps: [Double?] = [36.4, 36.45, 36.4, 36.5, 36.45, 36.4, 36.45, 36.5, 36.4, 36.45, 36.5, 36.45, 36.45,
                            36.65, 36.70, 36.75, 36.8, 36.8, 36.8]
    let mucus: [MucusSymbol?] = [nil, nil, nil, nil, .t, .t, .f, .s, .sPlus, .s, .f, .f, .s, .sPlus, .f, .t, .t, .t, .t]
    let c = makeCycle(temps: temps, mucus: mucus, bleedingDays: 4)
    let ctx = CycleEvaluator.CatalogContext(catalog: Catalog(name: "t", priorCycleCount: 3), previousCycleHadFirstHigher: true)
    let ev = CycleEvaluator.evaluate(cycle: c, context: ctx, options: EvaluationOptions(), today: c.endDate)
    eq(ev.mucus.peakDay, 14, "neuer Höhepunkt")
    eq(ev.mucus.completionDay, 17, "Schleim abgeschlossen")
    eq(ev.infertileFromEveningOfDay, 17, "Doppelkontrolle")

    // Strenge Auswertung: fehlender Eintrag zwischen Höhepunkt und Temperaturabschluss
    var mucus2 = mucus
    mucus2[13] = .s; mucus2[14] = nil // ZT 15 fehlt
    mucus2[8] = .sPlus
    let c2 = makeCycle(temps: temps, mucus: [nil, nil, nil, nil, .t, .t, .f, .s, .sPlus, .s, .f, .f, .f, .f, nil, .t, .t, .t, .t], bleedingDays: 4)
    let strict = CycleEvaluator.evaluate(cycle: c2, context: ctx, options: EvaluationOptions(lax: false), today: c2.endDate)
    eq(strict.mucus.status, .failed, "streng: Lücke → nicht auswertbar")
    check(strict.infertileFromEveningOfDay == nil, "streng: keine Unfruchtbarkeit")
    let lax = CycleEvaluator.evaluate(cycle: c2, context: ctx, options: EvaluationOptions(lax: true), today: c2.endDate)
    eq(lax.mucus.peakDay, 9, "lax: Höhepunkt")
    eq(lax.infertileFromEveningOfDay, 16, "lax: Doppelkontrolle (Temperatur ZT 16)")
    _ = mucus2
}

group("Muttermund") {
    var c = makeCycle(temps: lows + [36.4, 36.45, 36.4, 36.5, 36.65, 36.7, 36.75, 36.8])
    var entries = c.entries
    let pattern: [(CervixOpening, CervixFirmness)] = [
        (.closed, .hard), (.closed, .hard), (.closed, .hard), (.closed, .hard), (.closed, .hard), (.closed, .hard),
        (.partlyOpen, .soft), (.open, .soft), (.open, .soft), (.partlyOpen, .soft),
        (.closed, .hard), (.closed, .hard), (.closed, .hard), (.closed, .hard),
    ]
    for (i, p) in pattern.enumerated() {
        entries[i]?.cervix = CervixObservation(position: .low, opening: p.0, firmness: p.1)
    }
    c = Cycle(startDate: c.startDate, endDate: c.endDate, isCompleted: true, meta: c.meta, entries: entries)
    let ctx = CycleEvaluator.CatalogContext(catalog: Catalog(name: "m", priorCycleCount: 3), previousCycleHadFirstHigher: true)
    let ev = CycleEvaluator.evaluate(cycle: c, context: ctx, options: EvaluationOptions(doubleCheck: .cervix), today: c.endDate)
    eq(ev.cervix.peakDay, 10, "Muttermund-Höhepunkt = letzter fruchtbarer Tag")
    eq(ev.cervix.completionDay, 13, "Abschluss")
    eq(ev.temperature.completionDay, 13, "Temperatur")
    eq(ev.infertileFromEveningOfDay, 13, "Doppelkontrolle mit Muttermund")
}

group("Gesamtauswertung Demo-Daten") {
    let today = LocalDate(year: 2026, month: 10, day: 9)
    let data = DemoData.make(today: today)
    let cycles = CycleBuilder.cycles(from: data, today: today)
    eq(cycles.count, 6, "6 Zyklen")
    check(cycles.last?.isCompleted == false, "letzter Zyklus läuft")
    eq(cycles.last?.length, 19, "aktueller ZT 19")
    let evs = CycleEvaluator.evaluateAll(cycles: cycles, data: data, today: today)
    for c in cycles where c.isCompleted {
        let ev = evs[c.startDate]!
        check(ev.infertileFromEveningOfDay != nil, "Zyklus \(c.startDate) ausgewertet")
        check(ev.startPhase.infertileUntilDay > 0, "Zyklus \(c.startDate) Zyklusanfang")
    }
    let rows = Statistics.rows(cycles: cycles, evaluations: evs, data: data)
    let s = Statistics.summary(rows)
    eq(s.completedCount, 5, "5 abgeschlossene")
    check((s.averageHighPhase ?? 0) >= 12 && (s.averageHighPhase ?? 0) <= 16, "Hochlage plausibel: \(s.averageHighPhase ?? 0)")
    let current = evs[cycles.last!.startDate]!
    check(current.periodForecast != nil, "Periodenprognose vorhanden")
    let preds = PeriodPredictor.predict(cycles: cycles, evaluations: evs)
    eq(preds.count, 6, "6 Perioden prognostiziert")
    check(preds[0].basedOnTemperature, "erste Prognose nach Temperatur")
    let hits = Search.search("geburtstag", data: data, cycles: cycles)
    eq(hits.count, 1, "Suche")
    eq(hits.first?.cycleDay, 8, "Suche Zyklustag")
}

group("Schwangerschaft") {
    let today = LocalDate(year: 2026, month: 3, day: 1)
    var data = AppData()
    data.catalogs[0].priorCycleCount = 3
    var temps: [Double?] = lows + [36.45, 36.4]
    temps += Array(repeating: 36.9, count: 22)
    let c = makeCycle(temps: temps, completed: false)
    for e in c.entries.compactMap({ $0 }) { data.days[e.date] = e }
    let cycles = CycleBuilder.cycles(from: data, today: c.endDate)
    let evs = CycleEvaluator.evaluateAll(cycles: cycles, data: data, today: c.endDate)
    let ev = evs[c.startDate]!
    eq(ev.temperature.firstHigherDay, 9, "1.hM")
    check(ev.pregnancy != nil, "Schwangerschaft erkannt (Hochlagentag ≥ 19)")
    if let p = ev.pregnancy {
        eq(p.dueDate, c.date(ofDay: 9).adding(days: 266), "ET = 1.hM + 266")
        eq(p.weekLabel(on: c.date(ofDay: 9)), "SSW 2+0", "1.hM = SSW 2+0")
    }
    _ = today
}

group("Speicherung & Wiederherstellung") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nfpcheck-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DataStore(directory: dir)
    let first = store.load()
    check(first.isFirstLaunch, "Erststart")
    let data = DemoData.make(today: LocalDate(year: 2026, month: 10, day: 9))
    try store.save(data)
    var loaded = store.load()
    eq(loaded.data.days.count, data.days.count, "Roundtrip Tage")
    eq(normalized(loaded.data), normalized(data), "Roundtrip vollständig")
    check(loaded.recoveredFrom == nil, "keine Wiederherstellung nötig")

    // Zweite Speicherung → previous enthält ersten Stand
    var data2 = data
    data2.days.removeValue(forKey: data2.days.keys.max()!)
    try store.save(data2)
    // Hauptdatei beschädigen
    var raw = try Data(contentsOf: store.mainURL)
    raw[raw.count - 10] ^= 0xFF
    try raw.write(to: store.mainURL)
    loaded = store.load()
    eq(loaded.recoveredFrom, "letzter Speicherstand", "Wiederherstellung aus previous")
    eq(loaded.data.days.count, data.days.count, "Daten wiederhergestellt")

    // Snapshot
    check(store.snapshotIfNeeded(data), "Snapshot angelegt")
    check(!store.snapshotIfNeeded(data), "nur ein Snapshot pro Tag")
    eq(store.listSnapshots().count, 1, "Snapshot-Liste")
    check(store.safetySnapshot(data), "Sicherheits-Snapshot")
    eq(store.listSnapshots().filter(\.isSafety).count, 1, "Sicherheits-Snapshot gelistet")
    // Alles kaputt außer Snapshot
    try Data("kaputt".utf8).write(to: store.mainURL)
    try Data("kaputt".utf8).write(to: store.previousURL)
    loaded = store.load()
    check(loaded.recoveredFrom?.hasPrefix("Snapshot") == true, "Wiederherstellung aus Snapshot")
    eq(loaded.data.days.count, data.days.count, "Snapshot-Daten")
}

group("Backup-Verschlüsselung & ZIP") {
    let data = DemoData.make(today: LocalDate(year: 2026, month: 10, day: 9))
    let enc = try BackupCodec.encode(BackupPayload(data: data, appVersion: "1.0"), password: "geheim123")
    check(BackupCrypto.isEncrypted(enc), "verschlüsselt")
    check(!String(decoding: enc, as: UTF8.self).contains("temperature"), "kein Klartext")
    let dec = try BackupCodec.decode(enc, password: "geheim123")
    eq(normalized(dec.data), normalized(data), "entschlüsselt identisch")
    var wrongFailed = false
    do { _ = try BackupCodec.decode(enc, password: "falsch") } catch { wrongFailed = true }
    check(wrongFailed, "falsches Passwort scheitert")
    var noPwFailed = false
    do { _ = try BackupCodec.decode(enc, password: nil) } catch { noPwFailed = true }
    check(noPwFailed, "ohne Passwort scheitert")

    let cycles = CycleBuilder.cycles(from: data, today: LocalDate(year: 2026, month: 10, day: 9))
    let evs = CycleEvaluator.evaluateAll(cycles: cycles, data: data)
    let zip = try DataExporter.exportZip(data: data, cycles: cycles, evaluations: evs, appVersion: "1.0", password: nil)
    let entries = try ZipReader.entries(zip)
    check(entries["Tagesdaten.csv"] != nil, "CSV im ZIP")
    check(entries["Einstellungen.json"] != nil, "Einstellungen im ZIP")
    let fromZip = try BackupCodec.decode(zip, password: nil)
    eq(normalized(fromZip.data), normalized(data), "Import aus Export-ZIP")
    let encZip = try DataExporter.exportZip(data: data, cycles: cycles, evaluations: evs, appVersion: "1.0", password: "pw")
    check(BackupCodec.needsPassword(encZip), "verschlüsseltes ZIP erkannt")
    eq(normalized(try BackupCodec.decode(encZip, password: "pw").data), normalized(data), "Import aus verschlüsseltem ZIP")

    // Zusammenführen
    var cur = AppData()
    var e = DayEntry(date: LocalDate(year: 2020, month: 1, day: 1)); e.note = "alt"
    cur.days[e.date] = e
    let merged = DataMerger.merge(current: cur, imported: data, mode: .mergeKeepExisting)
    eq(merged.days.count, data.days.count + 1, "Zusammenführen")
}

print("")
if failures == 0 {
    print("✓ Alle \(passed) Prüfungen bestanden.")
    exit(0)
} else {
    print("✗ \(failures) Prüfungen fehlgeschlagen, \(passed) bestanden.")
    exit(1)
}
