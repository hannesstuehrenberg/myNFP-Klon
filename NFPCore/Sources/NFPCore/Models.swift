import Foundation

// MARK: - Blutung

public enum Bleeding: Int, Codable, CaseIterable, Sendable, Identifiable {
    case spotting = 1
    case light = 2
    case medium = 3
    case heavy = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .spotting: return "Schmierblutung"
        case .light: return "schwach"
        case .medium: return "mittel"
        case .heavy: return "stark"
        }
    }

    /// Darstellung im Zyklusblatt
    public var chartSymbol: String {
        switch self {
        case .spotting: return "•"
        case .light: return "x"
        case .medium: return "xx"
        case .heavy: return "xxx"
        }
    }
}

// MARK: - Zervixschleim

/// Was am Scheideneingang gefühlt/empfunden wurde.
public enum MucusFeeling: Int, Codable, CaseIterable, Sendable, Identifiable {
    case dry = 0        // trocken
    case nothing = 1    // nichts gefühlt
    case moist = 2      // feucht
    case wet = 3        // nass, rutschig, glitschig

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .dry: return "trocken"
        case .nothing: return "nichts gefühlt"
        case .moist: return "feucht"
        case .wet: return "nass / rutschig"
        }
    }

    public var detail: String {
        switch self {
        case .dry: return "trockenes, raues, juckendes, unangenehmes Gefühl"
        case .nothing: return "keine Feuchtigkeit, keine Empfindung"
        case .moist: return "feuchtes Gefühl"
        case .wet: return "nass, schlüpfrig, rutschig, glitschig, wie eingeölt, glatt"
        }
    }
}

/// Was gesehen wurde. Mehrfachauswahl, die fruchtbarste Eigenschaft zählt.
public enum MucusAppearance: String, Codable, CaseIterable, Sendable, Identifiable {
    // Kategorie S
    case thick = "dicklich"
    case whitish = "weißlich"
    case cloudy = "trüb"
    case creamy = "cremig"
    case lumpy = "klumpig"
    case yellowish = "gelblich"
    case sticky = "klebrig"
    case milky = "milchig"
    case notStretchy = "nicht ziehbar"
    case tough = "zäh"
    // Kategorie S+
    case glassy = "glasig"
    case transparent = "durchsichtig"
    case stretchy = "dehnbar"
    case stringy = "fadenziehend"
    case spinnbar = "spinnbar"
    case eggWhite = "wie rohes Eiweiß"

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var isSPlus: Bool {
        switch self {
        case .glassy, .transparent, .stretchy, .stringy, .spinnbar, .eggWhite: return true
        default: return false
        }
    }

    public static var sCategory: [MucusAppearance] { allCases.filter { !$0.isSPlus } }
    public static var sPlusCategory: [MucusAppearance] { allCases.filter { $0.isSPlus } }
}

/// Symbole der symptothermalen Methode, sortiert von schlechter zu besser.
public enum MucusSymbol: Int, Codable, CaseIterable, Comparable, Sendable, Identifiable {
    case t = 0
    case nothing = 1
    case f = 2
    case s = 3
    case sPlus = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .t: return "t"
        case .nothing: return "∅"
        case .f: return "f"
        case .s: return "S"
        case .sPlus: return "S+"
        }
    }

    public var meaning: String {
        switch self {
        case .t: return "trocken"
        case .nothing: return "nichts gefühlt, nichts gesehen"
        case .f: return "feucht, nichts gesehen"
        case .s: return "Schleim: dicklich, weißlich, trüb, cremig …"
        case .sPlus: return "Schleim: glasig, dehnbar, spinnbar oder nass/rutschig"
        }
    }

    public static func < (l: MucusSymbol, r: MucusSymbol) -> Bool { l.rawValue < r.rawValue }
}

public struct MucusObservation: Codable, Hashable, Sendable {
    public var feeling: MucusFeeling?
    public var appearance: Set<MucusAppearance>
    /// Direkt gesetztes Symbol (z. B. über die Schnelleingabe). Hat Vorrang vor der Ableitung.
    public var manualSymbol: MucusSymbol?
    /// Binnendifferenzierung: (S) bzw. (S+) – etwas schlechter als üblich für die Kategorie.
    public var reduced: Bool

    public init(feeling: MucusFeeling? = nil, appearance: Set<MucusAppearance> = [],
                manualSymbol: MucusSymbol? = nil, reduced: Bool = false) {
        self.feeling = feeling
        self.appearance = appearance
        self.manualSymbol = manualSymbol
        self.reduced = reduced
    }

    public static func symbol(_ s: MucusSymbol, reduced: Bool = false) -> MucusObservation {
        MucusObservation(manualSymbol: s, reduced: reduced)
    }

    public var isEmpty: Bool { feeling == nil && appearance.isEmpty && manualSymbol == nil }

    /// Ableitung des Symbols anhand der Zervixschleim-Tabelle. Die fruchtbarste Eigenschaft zählt.
    public var symbol: MucusSymbol? {
        if let manualSymbol { return manualSymbol }
        if isEmpty { return nil }
        if feeling == .wet || appearance.contains(where: { $0.isSPlus }) { return .sPlus }
        if !appearance.isEmpty { return .s }
        switch feeling {
        case .moist: return .f
        case .nothing: return .nothing
        case .dry: return .t
        default: return nil
        }
    }

    /// Feine Qualitätsstufe für den Vergleich (berücksichtigt (S)/(S+)).
    /// t=0, ∅=2, f=4, (S)=5, S=6, (S+)=7, S+=8
    public var qualityRank: Int? {
        guard let s = symbol else { return nil }
        let base = s.rawValue * 2
        if reduced && (s == .s || s == .sPlus) { return base - 1 }
        return base
    }

    public var displaySymbol: String? {
        guard let s = symbol else { return nil }
        if reduced && (s == .s || s == .sPlus) { return "(\(s.label))" }
        return s.label
    }
}

// MARK: - Muttermund

public enum CervixPosition: Int, Codable, CaseIterable, Sendable, Identifiable {
    case low = 0, medium = 1, high = 2
    public var id: Int { rawValue }
    public var label: String {
        switch self { case .low: return "tief"; case .medium: return "mittel"; case .high: return "hoch" }
    }
}

public enum CervixOpening: Int, Codable, CaseIterable, Sendable, Identifiable {
    case closed = 0, partlyOpen = 1, open = 2
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .closed: return "geschlossen"
        case .partlyOpen: return "leicht geöffnet"
        case .open: return "geöffnet"
        }
    }
    public var symbol: String {
        switch self { case .closed: return "●"; case .partlyOpen: return "◐"; case .open: return "○" }
    }
}

public enum CervixFirmness: Int, Codable, CaseIterable, Sendable, Identifiable {
    case hard = 0, soft = 1
    public var id: Int { rawValue }
    public var label: String { self == .hard ? "hart" : "weich" }
    public var letter: String { self == .hard ? "H" : "W" }
}

public struct CervixObservation: Codable, Hashable, Sendable {
    public var position: CervixPosition?
    public var opening: CervixOpening?
    public var firmness: CervixFirmness?

    public init(position: CervixPosition? = nil, opening: CervixOpening? = nil, firmness: CervixFirmness? = nil) {
        self.position = position
        self.opening = opening
        self.firmness = firmness
    }

    public var isEmpty: Bool { position == nil && opening == nil && firmness == nil }
    /// Öffnung und Härte sind für die Auswertung nötig.
    public var isComplete: Bool { opening != nil && firmness != nil }

    /// Unfruchtbares Muster: geschlossen und hart.
    public var isClosedAndHard: Bool { opening == .closed && firmness == .hard }

    /// Fruchtbarkeitsgrad (größer = fruchtbarer). nil bei unvollständiger Angabe.
    public var fertilityScore: Int? {
        guard let o = opening, let f = firmness else { return nil }
        return o.rawValue * 2 + f.rawValue * 2 + (position?.rawValue ?? 0)
    }

    public var displaySymbol: String? {
        if isEmpty { return nil }
        let o = opening?.symbol ?? "?"
        let f = firmness?.letter ?? ""
        return o + f
    }
}

// MARK: - Weitere Symptome

public enum BreastSymptom: Int, Codable, CaseIterable, Sendable, Identifiable {
    case tension = 1   // B: Brustspannen
    case pain = 2      // BS: Brustschmerz/-empfindlichkeit
    public var id: Int { rawValue }
    public var label: String { self == .tension ? "Brustspannen" : "Brustschmerz / empfindlich" }
    public var symbol: String { self == .tension ? "B" : "BS" }
}

public enum MittelschmerzSide: Int, Codable, CaseIterable, Sendable, Identifiable {
    case unspecified = 0, left = 1, right = 2, both = 3
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .unspecified: return "ja"
        case .left: return "links"
        case .right: return "rechts"
        case .both: return "beidseitig"
        }
    }
    public var symbol: String {
        switch self { case .unspecified: return "M"; case .left: return "Ml"; case .right: return "Mr"; case .both: return "Mb" }
    }
}

public enum Intercourse: Int, Codable, CaseIterable, Sendable, Identifiable {
    case unprotected = 1
    case protected = 2
    public var id: Int { rawValue }
    public var label: String { self == .unprotected ? "Geschlechtsverkehr" : "geschützter Geschlechtsverkehr" }
    public var symbol: String { self == .unprotected ? "GV" : "gGV" }
}

/// Störfaktoren der Temperaturmessung
public enum Disturbance: String, Codable, CaseIterable, Sendable, Identifiable {
    case alcohol = "Alkohol"
    case lateNight = "spät ins Bett"
    case littleSleep = "wenig / schlecht geschlafen"
    case illness = "Krankheit / Fieber"
    case stress = "Stress"
    case travel = "Reise / Zeitumstellung"
    case differentTime = "abweichende Messzeit"
    case medication = "Medikamente"
    case otherThermometer = "anderes Thermometer"
    case other = "Sonstiges"
    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum MeasurementSite: String, Codable, CaseIterable, Sendable, Identifiable {
    case oral = "oral"
    case vaginal = "vaginal"
    case rectal = "rektal"
    public var id: String { rawValue }
    public var label: String { rawValue }
}

// MARK: - Zusatzleisten

public enum BarKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case singleChoice      // Auswahlfeld
    case multiChoice       // Mehrfachauswahl
    case textValue         // Textfeld (zeigt Wert)
    case textIcon          // Textfeld (zeigt Icon)
    case sliderRedGreen    // Slider 1–5 (1 rot … 5 grün)
    case sliderGreenRed    // Slider 1–5 (1 grün … 5 rot)
    case goalReached       // Ziel erreicht (Zielfahne)
    case done              // Erledigt
    case takenYes          // Eingenommen (zeigt „ja“)
    case takenIcon         // Eingenommen (grünes Häkchen)
    case intensity         // Intensität (sehr schwach … sehr stark)

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .singleChoice: return "Auswahlfeld"
        case .multiChoice: return "Mehrfachauswahl"
        case .textValue: return "Textfeld (zeigt Wert)"
        case .textIcon: return "Textfeld (zeigt Icon)"
        case .sliderRedGreen: return "Slider 1–5 (rot → grün)"
        case .sliderGreenRed: return "Slider 1–5 (grün → rot)"
        case .goalReached: return "Ziel erreicht (ja/nein)"
        case .done: return "Erledigt (ja/nein)"
        case .takenYes: return "Eingenommen (zeigt „ja“)"
        case .takenIcon: return "Eingenommen (zeigt Häkchen)"
        case .intensity: return "Intensität"
        }
    }

    public var usesOptions: Bool { self == .singleChoice || self == .multiChoice }
    public var isYesNo: Bool { [.goalReached, .done, .takenYes, .takenIcon].contains(self) }
    public var isSlider: Bool { self == .sliderRedGreen || self == .sliderGreenRed }

    public static let intensityLevels = ["sehr schwach", "schwach", "mittel", "stark", "sehr stark"]
}

public struct BarDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: BarKind
    public var options: [String]
    public var isVisible: Bool
    /// Symbol im Zyklusblatt (SF Symbol Name), falls die Leiste ein Icon zeigt
    public var icon: String?

    public init(id: String = UUID().uuidString, name: String, kind: BarKind, options: [String] = [],
                isVisible: Bool = true, icon: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.options = options
        self.isVisible = isVisible
        self.icon = icon
    }
}

public struct BarValue: Codable, Hashable, Sendable {
    /// Gewählte Optionen (Auswahlfeld: genau eine, Mehrfachauswahl: mehrere, Intensität: eine Stufe)
    public var selections: [String]
    public var text: String?
    /// Slider 1–5
    public var number: Int?
    /// Ja/Nein-Leisten
    public var flag: Bool?

    public init(selections: [String] = [], text: String? = nil, number: Int? = nil, flag: Bool? = nil) {
        self.selections = selections
        self.text = text
        self.number = number
        self.flag = flag
    }

    public var isEmpty: Bool {
        selections.isEmpty && (text?.isEmpty ?? true) && number == nil && flag == nil
    }
}

// MARK: - Tagesdaten

public struct DayEntry: Codable, Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var id: LocalDate { date }

    /// Temperatur in °C, gerundet auf 0,05 °C
    public var temperature: Double?
    /// Messuhrzeit in Minuten seit Mitternacht
    public var measurementTime: Int?
    /// Ausgeklammert (gestörter Wert, wird bei der Auswertung ignoriert)
    public var excluded: Bool
    public var disturbances: Set<Disturbance>

    public var bleeding: Bleeding?
    public var isFirstCycleDay: Bool

    public var mucus: MucusObservation?
    public var cervix: CervixObservation?
    public var breast: BreastSymptom?
    public var mittelschmerz: MittelschmerzSide?
    public var intercourse: Intercourse?

    public var note: String?
    public var medication: String?
    public var bars: [String: BarValue]

    public init(date: LocalDate) {
        self.date = date
        self.excluded = false
        self.disturbances = []
        self.isFirstCycleDay = false
        self.bars = [:]
    }

    public var hasData: Bool {
        temperature != nil || measurementTime != nil || excluded || !disturbances.isEmpty
            || bleeding != nil || isFirstCycleDay
            || !(mucus?.isEmpty ?? true) || !(cervix?.isEmpty ?? true)
            || breast != nil || mittelschmerz != nil || intercourse != nil
            || !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(medication?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || bars.values.contains { !$0.isEmpty }
    }

    /// Für die Auswertung gültige Temperatur (nicht ausgeklammert)
    public var validTemperature: Double? { excluded ? nil : temperature }

    // Tolerante Dekodierung, damit ältere/neuere Backups lesbar bleiben
    enum CodingKeys: String, CodingKey {
        case date, temperature, measurementTime, excluded, disturbances, bleeding, isFirstCycleDay,
             mucus, cervix, breast, mittelschmerz, intercourse, note, medication, bars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        measurementTime = try c.decodeIfPresent(Int.self, forKey: .measurementTime)
        excluded = try c.decodeIfPresent(Bool.self, forKey: .excluded) ?? false
        disturbances = try c.decodeIfPresent(Set<Disturbance>.self, forKey: .disturbances) ?? []
        bleeding = try c.decodeIfPresent(Bleeding.self, forKey: .bleeding)
        isFirstCycleDay = try c.decodeIfPresent(Bool.self, forKey: .isFirstCycleDay) ?? false
        mucus = try c.decodeIfPresent(MucusObservation.self, forKey: .mucus)
        cervix = try c.decodeIfPresent(CervixObservation.self, forKey: .cervix)
        breast = try c.decodeIfPresent(BreastSymptom.self, forKey: .breast)
        mittelschmerz = try c.decodeIfPresent(MittelschmerzSide.self, forKey: .mittelschmerz)
        intercourse = try c.decodeIfPresent(Intercourse.self, forKey: .intercourse)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        medication = try c.decodeIfPresent(String.self, forKey: .medication)
        bars = try c.decodeIfPresent([String: BarValue].self, forKey: .bars) ?? [:]
    }
}

// MARK: - Zyklus-Einstellungen & manuelle Auswertung

public struct ManualEvaluation: Codable, Hashable, Sendable {
    /// Letzter unfruchtbarer Tag am Zyklusanfang (Zyklustag), 0 = keiner
    public var infertileStartUntilDay: Int?
    public var coverline: Double?
    public var firstHigherDay: Int?
    public var mucusPeakDay: Int?
    public var cervixPeakDay: Int?
    /// Ab dem Abend dieses Zyklustages unfruchtbar
    public var infertileFromEveningOfDay: Int?

    public init() {}
}

public struct CycleMeta: Codable, Hashable, Sendable {
    public var catalogID: UUID?
    public var measurementSite: MeasurementSite?
    public var measurementDurationMinutes: Int?
    public var thermometer: String?
    public var wantsChild: Bool
    public var useManualEvaluation: Bool
    public var manual: ManualEvaluation
    public var comment: String?

    public init(catalogID: UUID? = nil) {
        self.catalogID = catalogID
        self.wantsChild = false
        self.useManualEvaluation = false
        self.manual = ManualEvaluation()
    }

    enum CodingKeys: String, CodingKey {
        case catalogID, measurementSite, measurementDurationMinutes, thermometer, wantsChild,
             useManualEvaluation, manual, comment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        catalogID = try c.decodeIfPresent(UUID.self, forKey: .catalogID)
        measurementSite = try c.decodeIfPresent(MeasurementSite.self, forKey: .measurementSite)
        measurementDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .measurementDurationMinutes)
        thermometer = try c.decodeIfPresent(String.self, forKey: .thermometer)
        wantsChild = try c.decodeIfPresent(Bool.self, forKey: .wantsChild) ?? false
        useManualEvaluation = try c.decodeIfPresent(Bool.self, forKey: .useManualEvaluation) ?? false
        manual = try c.decodeIfPresent(ManualEvaluation.self, forKey: .manual) ?? ManualEvaluation()
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
    }
}

// MARK: - Katalog

public struct Catalog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Anzahl früher ausgewerteter Zyklen (z. B. auf Papier oder in einer anderen App) mit 1. höherer Messung
    public var priorCycleCount: Int
    /// Früheste 1. höhere Messung aus früheren Aufzeichnungen (Zyklustag)
    public var priorEarliestFirstHigher: Int?
    /// Kürzester Zyklus der letzten 12 Zyklen (für die Minus-20-Regel)
    public var shortestCycleForMinus20: Int?
    /// Unmittelbar vor Beginn der Aufzeichnungen hormonell verhütet (Post-Pill-Regeln)
    public var postPill: Bool
    /// Verschiebung des roten Prognose-Balkens in Tagen
    public var periodForecastShift: Int
    /// Feste Temperaturskala für alle Zyklen dieses Katalogs
    public var fixedTemperatureScale: Bool
    public var comment: String?

    public init(id: UUID = UUID(), name: String, priorCycleCount: Int = 0, priorEarliestFirstHigher: Int? = nil,
                shortestCycleForMinus20: Int? = nil, postPill: Bool = false, periodForecastShift: Int = 0,
                fixedTemperatureScale: Bool = false) {
        self.id = id
        self.name = name
        self.priorCycleCount = priorCycleCount
        self.priorEarliestFirstHigher = priorEarliestFirstHigher
        self.shortestCycleForMinus20 = shortestCycleForMinus20
        self.postPill = postPill
        self.periodForecastShift = periodForecastShift
        self.fixedTemperatureScale = fixedTemperatureScale
    }

    enum CodingKeys: String, CodingKey {
        case id, name, priorCycleCount, priorEarliestFirstHigher, shortestCycleForMinus20, postPill,
             periodForecastShift, fixedTemperatureScale, comment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        priorCycleCount = try c.decodeIfPresent(Int.self, forKey: .priorCycleCount) ?? 0
        priorEarliestFirstHigher = try c.decodeIfPresent(Int.self, forKey: .priorEarliestFirstHigher)
        shortestCycleForMinus20 = try c.decodeIfPresent(Int.self, forKey: .shortestCycleForMinus20)
        postPill = try c.decodeIfPresent(Bool.self, forKey: .postPill) ?? false
        periodForecastShift = try c.decodeIfPresent(Int.self, forKey: .periodForecastShift) ?? 0
        fixedTemperatureScale = try c.decodeIfPresent(Bool.self, forKey: .fixedTemperatureScale) ?? false
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
    }
}

// MARK: - App-Einstellungen

public enum DoubleCheckSymptom: String, Codable, CaseIterable, Sendable, Identifiable {
    case mucus, cervix
    public var id: String { rawValue }
    public var label: String { self == .mucus ? "Zervixschleim" : "Muttermund" }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var label: String {
        switch self { case .system: return "System"; case .light: return "Hell"; case .dark: return "Dunkel" }
    }
}

/// Fest eingebaute Zeilen im Zyklusblatt / in der Tageseingabe
public enum CoreRow: String, Codable, CaseIterable, Sendable, Identifiable {
    case time, bleeding, mucus, cervix, breast, mittelschmerz, intercourse, disturbances, note, medication
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .time: return "Messuhrzeit"
        case .bleeding: return "Blutung"
        case .mucus: return "Zervixschleim"
        case .cervix: return "Muttermund"
        case .breast: return "Brustsymptom"
        case .mittelschmerz: return "Mittelschmerz"
        case .intercourse: return "Geschlechtsverkehr"
        case .disturbances: return "Störungen"
        case .note: return "Notiz"
        case .medication: return "Medikamente"
        }
    }
}

public struct NotificationSettings: Codable, Hashable, Sendable {
    /// Erinnerung zum Temperaturmessen
    public var measureReminderEnabled: Bool
    public var measureReminderMinutes: Int
    public var measureReminderWeekendMinutes: Int?
    /// „Periode in X Tagen“
    public var periodReminderEnabled: Bool
    public var periodReminderDaysBefore: Int
    /// „Brust abtasten“ an Zyklustag X
    public var breastExamEnabled: Bool
    public var breastExamCycleDay: Int
    /// Hinweis, wenn die fruchtbare Phase beginnt / endet
    public var phaseChangeEnabled: Bool
    /// Erinnerung, ein externes Backup anzulegen
    public var backupReminderEnabled: Bool
    public var reminderMinutes: Int

    public init() {
        measureReminderEnabled = false
        measureReminderMinutes = 6 * 60 + 30
        measureReminderWeekendMinutes = nil
        periodReminderEnabled = false
        periodReminderDaysBefore = 3
        breastExamEnabled = false
        breastExamCycleDay = 7
        phaseChangeEnabled = false
        backupReminderEnabled = true
        reminderMinutes = 8 * 60
    }

    enum CodingKeys: String, CodingKey {
        case measureReminderEnabled, measureReminderMinutes, measureReminderWeekendMinutes, periodReminderEnabled,
             periodReminderDaysBefore, breastExamEnabled, breastExamCycleDay, phaseChangeEnabled,
             backupReminderEnabled, reminderMinutes
    }

    public init(from decoder: Decoder) throws {
        let d = NotificationSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measureReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .measureReminderEnabled) ?? d.measureReminderEnabled
        measureReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .measureReminderMinutes) ?? d.measureReminderMinutes
        measureReminderWeekendMinutes = try c.decodeIfPresent(Int.self, forKey: .measureReminderWeekendMinutes)
        periodReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .periodReminderEnabled) ?? d.periodReminderEnabled
        periodReminderDaysBefore = try c.decodeIfPresent(Int.self, forKey: .periodReminderDaysBefore) ?? d.periodReminderDaysBefore
        breastExamEnabled = try c.decodeIfPresent(Bool.self, forKey: .breastExamEnabled) ?? d.breastExamEnabled
        breastExamCycleDay = try c.decodeIfPresent(Int.self, forKey: .breastExamCycleDay) ?? d.breastExamCycleDay
        phaseChangeEnabled = try c.decodeIfPresent(Bool.self, forKey: .phaseChangeEnabled) ?? d.phaseChangeEnabled
        backupReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .backupReminderEnabled) ?? d.backupReminderEnabled
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? d.reminderMinutes
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    // Fortgeschrittenen-Modus
    public var advancedMode: Bool
    public var laxEvaluation: Bool
    public var mucusSubdifferentiation: Bool
    public var quickEntryEnabled: Bool
    public var hideHelpTexts: Bool
    public var cycleStartByCervix: Bool
    public var doubleCheck: DoubleCheckSymptom

    // Darstellung
    public var highlightRelevantTemperatures: Bool
    public var zoomPercent: Int
    public var appearance: AppearanceMode
    public var hidePregnancyBar: Bool
    public var hideDueDate: Bool
    public var hidePregnancyWeek: Bool
    public var hiddenCoreRows: Set<CoreRow>

    // Zusatzleisten in Reihenfolge
    public var bars: [BarDefinition]

    public var notifications: NotificationSettings

    /// Wurde der Hinweis zur Zweckbestimmung bestätigt?
    public var acceptedDisclaimer: Bool

    public init() {
        advancedMode = false
        laxEvaluation = false
        mucusSubdifferentiation = false
        quickEntryEnabled = false
        hideHelpTexts = false
        cycleStartByCervix = false
        doubleCheck = .mucus
        highlightRelevantTemperatures = true
        zoomPercent = 115
        appearance = .system
        hidePregnancyBar = false
        hideDueDate = false
        hidePregnancyWeek = false
        hiddenCoreRows = [.cervix]
        bars = DefaultBars.all
        notifications = NotificationSettings()
        acceptedDisclaimer = false
    }

    /// Effektive Werte: Optionen des Fortgeschrittenen-Modus wirken nur, wenn er aktiv ist.
    public var effectiveLax: Bool { advancedMode && laxEvaluation }
    public var effectiveSubdifferentiation: Bool { advancedMode && mucusSubdifferentiation }
    public var effectiveQuickEntry: Bool { advancedMode && quickEntryEnabled }
    public var effectiveCycleStartByCervix: Bool { advancedMode && cycleStartByCervix }

    enum CodingKeys: String, CodingKey {
        case advancedMode, laxEvaluation, mucusSubdifferentiation, quickEntryEnabled, hideHelpTexts,
             cycleStartByCervix, doubleCheck, highlightRelevantTemperatures, zoomPercent, appearance,
             hidePregnancyBar, hideDueDate, hidePregnancyWeek, hiddenCoreRows, bars, notifications,
             acceptedDisclaimer
    }

    public init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        advancedMode = try c.decodeIfPresent(Bool.self, forKey: .advancedMode) ?? d.advancedMode
        laxEvaluation = try c.decodeIfPresent(Bool.self, forKey: .laxEvaluation) ?? d.laxEvaluation
        mucusSubdifferentiation = try c.decodeIfPresent(Bool.self, forKey: .mucusSubdifferentiation) ?? d.mucusSubdifferentiation
        quickEntryEnabled = try c.decodeIfPresent(Bool.self, forKey: .quickEntryEnabled) ?? d.quickEntryEnabled
        hideHelpTexts = try c.decodeIfPresent(Bool.self, forKey: .hideHelpTexts) ?? d.hideHelpTexts
        cycleStartByCervix = try c.decodeIfPresent(Bool.self, forKey: .cycleStartByCervix) ?? d.cycleStartByCervix
        doubleCheck = try c.decodeIfPresent(DoubleCheckSymptom.self, forKey: .doubleCheck) ?? d.doubleCheck
        highlightRelevantTemperatures = try c.decodeIfPresent(Bool.self, forKey: .highlightRelevantTemperatures) ?? d.highlightRelevantTemperatures
        zoomPercent = try c.decodeIfPresent(Int.self, forKey: .zoomPercent) ?? d.zoomPercent
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? d.appearance
        hidePregnancyBar = try c.decodeIfPresent(Bool.self, forKey: .hidePregnancyBar) ?? d.hidePregnancyBar
        hideDueDate = try c.decodeIfPresent(Bool.self, forKey: .hideDueDate) ?? d.hideDueDate
        hidePregnancyWeek = try c.decodeIfPresent(Bool.self, forKey: .hidePregnancyWeek) ?? d.hidePregnancyWeek
        hiddenCoreRows = try c.decodeIfPresent(Set<CoreRow>.self, forKey: .hiddenCoreRows) ?? d.hiddenCoreRows
        bars = try c.decodeIfPresent([BarDefinition].self, forKey: .bars) ?? d.bars
        notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? d.notifications
        acceptedDisclaimer = try c.decodeIfPresent(Bool.self, forKey: .acceptedDisclaimer) ?? d.acceptedDisclaimer
    }
}

// MARK: - Gesamtdatenbestand

public struct AppData: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var days: [LocalDate: DayEntry]
    /// Zyklus-Einstellungen, Schlüssel = 1. Zyklustag
    public var cycleMeta: [LocalDate: CycleMeta]
    /// Reihenfolge = Anzeige-Reihenfolge, der oberste ist der Hauptkatalog
    public var catalogs: [Catalog]
    public var settings: AppSettings
    public var modifiedAt: Date

    public init() {
        schemaVersion = AppData.currentSchemaVersion
        days = [:]
        cycleMeta = [:]
        catalogs = [Catalog(name: "Hauptkatalog")]
        settings = AppSettings()
        modifiedAt = Date()
    }

    public var mainCatalog: Catalog { catalogs[0] }

    public func catalog(id: UUID?) -> Catalog {
        catalogs.first { $0.id == id } ?? catalogs[0]
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, days, cycleMeta, catalogs, settings, modifiedAt
    }

    private struct MetaRecord: Codable {
        var start: LocalDate
        var meta: CycleMeta
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let dayList = try c.decodeIfPresent([DayEntry].self, forKey: .days) ?? []
        days = Dictionary(dayList.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let metaList = try c.decodeIfPresent([MetaRecord].self, forKey: .cycleMeta) ?? []
        cycleMeta = Dictionary(metaList.map { ($0.start, $0.meta) }, uniquingKeysWith: { a, _ in a })
        var cats = try c.decodeIfPresent([Catalog].self, forKey: .catalogs) ?? []
        if cats.isEmpty { cats = [Catalog(name: "Hauptkatalog")] }
        catalogs = cats
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(days.values.sorted { $0.date < $1.date }, forKey: .days)
        try c.encode(cycleMeta.map { MetaRecord(start: $0.key, meta: $0.value) }.sorted { $0.start < $1.start },
                     forKey: .cycleMeta)
        try c.encode(catalogs, forKey: .catalogs)
        try c.encode(settings, forKey: .settings)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}
