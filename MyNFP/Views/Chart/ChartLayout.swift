import SwiftUI
import NFPCore

/// Zeilen des Zyklusblatts
enum ChartRowKind: Hashable {
    case date
    case time
    case bars          // roter Prognose-Balken / lila Schwangerschafts-Balken
    case temperature
    case cycleDay
    case status
    case bleeding
    case mucus
    case peak
    case cervix
    case breast
    case mittelschmerz
    case intercourse
    case disturbances
    case note
    case medication
    case extra(String) // Zusatzleiste

    var label: String {
        switch self {
        case .date: return "Datum"
        case .time: return "Uhrzeit"
        case .bars: return ""
        case .temperature: return "°C"
        case .cycleDay: return "ZT"
        case .status: return "Auswertung"
        case .bleeding: return "Blutung"
        case .mucus: return "Schleim"
        case .peak: return "Höhepunkt"
        case .cervix: return "Muttermund"
        case .breast: return "Brust"
        case .mittelschmerz: return "Mittelschm."
        case .intercourse: return "GV"
        case .disturbances: return "Störungen"
        case .note: return "Notiz"
        case .medication: return "Medikam."
        case .extra: return ""
        }
    }
}

struct ChartRow: Hashable {
    let kind: ChartRowKind
    let y: CGFloat
    let height: CGFloat
    let label: String
}

/// Alle Daten, die zum Zeichnen eines Zyklusblatts nötig sind (auch für PDF/Bild-Export).
struct ChartContext {
    let cycle: Cycle
    let evaluation: CycleEvaluation?
    let settings: AppSettings
    let tempRange: ClosedRange<Double>
    let today: LocalDate
    let selectedDay: Int?
    /// Anzahl dargestellter Spalten (beim laufenden Zyklus inkl. einiger Zukunftstage)
    let dayCount: Int
    let zoom: CGFloat

    var wantsChild: Bool { cycle.meta.wantsChild }

    init(cycle: Cycle, evaluation: CycleEvaluation?, settings: AppSettings, tempRange: ClosedRange<Double>,
         today: LocalDate, selectedDay: Int?, zoomOverride: CGFloat? = nil) {
        self.cycle = cycle
        self.evaluation = evaluation
        self.settings = settings
        self.tempRange = tempRange
        self.today = today
        self.selectedDay = selectedDay
        self.zoom = zoomOverride ?? CGFloat(settings.zoomPercent) / 100
        var count = cycle.length
        if !cycle.isCompleted {
            count = max(count, 28)
            if let f = evaluation?.periodForecast {
                count = max(count, cycle.cycleDay(of: f.latest) + 1)
            }
            if let p = evaluation?.pregnancy, !settings.hidePregnancyBar {
                count = max(count, cycle.cycleDay(of: today) + 3)
                _ = p
            }
        }
        self.dayCount = min(count, 999)
    }

    func date(ofDay d: Int) -> LocalDate { cycle.date(ofDay: d) }

    func entry(_ d: Int) -> DayEntry? { cycle.entry(day: d) }
}

struct ChartLayout {
    let colW: CGFloat
    let labelW: CGFloat
    let stepH: CGFloat // Höhe pro 0,05 °C
    let rows: [ChartRow]
    let totalHeight: CGFloat
    let dayCount: Int
    let tempRange: ClosedRange<Double>

    init(context ctx: ChartContext, bars: [BarDefinition]) {
        let z = ctx.zoom
        colW = (24 * z).rounded()
        labelW = 74
        stepH = 8 * z
        dayCount = ctx.dayCount
        tempRange = ctx.tempRange
        let hidden = ctx.settings.hiddenCoreRows

        var rows: [ChartRow] = []
        var y: CGFloat = 0
        func add(_ kind: ChartRowKind, _ h: CGFloat, _ label: String? = nil) {
            rows.append(ChartRow(kind: kind, y: y, height: h, label: label ?? kind.label))
            y += h
        }
        add(.date, 34 * z)
        if !hidden.contains(.time) { add(.time, 15 * z) }
        add(.bars, 9 * z)
        let tempH = CGFloat((ctx.tempRange.upperBound - ctx.tempRange.lowerBound) / 0.05) * stepH
        add(.temperature, tempH)
        add(.cycleDay, 16 * z)
        add(.status, 12 * z)
        let rowH = 20 * z
        if !hidden.contains(.bleeding) { add(.bleeding, rowH) }
        if !hidden.contains(.mucus) { add(.mucus, rowH) }
        add(.peak, rowH)
        if !hidden.contains(.cervix) { add(.cervix, rowH) }
        if !hidden.contains(.breast) { add(.breast, rowH) }
        if !hidden.contains(.mittelschmerz) { add(.mittelschmerz, rowH) }
        if !hidden.contains(.intercourse) { add(.intercourse, rowH) }
        if !hidden.contains(.disturbances) { add(.disturbances, rowH) }
        if !hidden.contains(.note) { add(.note, rowH) }
        if !hidden.contains(.medication) { add(.medication, rowH) }
        for bar in bars where bar.isVisible {
            add(.extra(bar.id), rowH, bar.name)
        }
        self.rows = rows
        totalHeight = y + 4
    }

    var contentWidth: CGFloat { CGFloat(dayCount) * colW }

    func row(_ kind: ChartRowKind) -> ChartRow? { rows.first { $0.kind == kind } }

    func xCenter(_ day: Int) -> CGFloat { (CGFloat(day) - 0.5) * colW }
    func xLeft(_ day: Int) -> CGFloat { CGFloat(day - 1) * colW }

    func y(temp: Double) -> CGFloat {
        guard let r = row(.temperature) else { return 0 }
        let clamped = min(max(temp, tempRange.lowerBound), tempRange.upperBound)
        let frac = (tempRange.upperBound - clamped) / (tempRange.upperBound - tempRange.lowerBound)
        return r.y + CGFloat(frac) * r.height
    }

    func day(atX x: CGFloat) -> Int {
        max(1, min(dayCount, Int(x / colW) + 1))
    }
}
