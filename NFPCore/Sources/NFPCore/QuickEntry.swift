import Foundation

/// Schnelleingabe (Fortgeschrittenen-Modus), z. B. „3667 ggv bs s+ 623 # Notiz“.
/// Die Reihenfolge der Angaben spielt keine Rolle.
public struct QuickEntryResult: Equatable, Sendable {
    public var temperature: Double?
    public var time: Int?
    public var mucus: MucusObservation?
    public var bleeding: Bleeding?
    public var mittelschmerz: MittelschmerzSide?
    public var breast: BreastSymptom?
    public var intercourse: Intercourse?
    public var excluded: Bool?
    public var firstCycleDay: Bool?
    public var note: String?
    public var unrecognized: [String] = []

    public init() {}

    public var isEmpty: Bool {
        temperature == nil && time == nil && mucus == nil && bleeding == nil && mittelschmerz == nil
            && breast == nil && intercourse == nil && excluded == nil && firstCycleDay == nil && note == nil
    }

    /// Überträgt die erkannten Angaben in einen Tageseintrag (nicht erkannte Felder bleiben unverändert).
    public func apply(to entry: inout DayEntry) {
        if let temperature { entry.temperature = temperature }
        if let time { entry.measurementTime = time }
        if let mucus { entry.mucus = mucus }
        if let bleeding { entry.bleeding = bleeding }
        if let mittelschmerz { entry.mittelschmerz = mittelschmerz }
        if let breast { entry.breast = breast }
        if let intercourse { entry.intercourse = intercourse }
        if let excluded { entry.excluded = excluded }
        if let firstCycleDay { entry.isFirstCycleDay = firstCycleDay }
        if let note {
            if let old = entry.note, !old.isEmpty, old != note { entry.note = old + " " + note } else { entry.note = note }
        }
    }
}

public enum QuickEntryParser {
    public static let helpText = """
    Temperatur: „3667“ oder nur Nachkommastellen „67“ (= 36,65); „370“ = 37,00
    Uhrzeit: „623“ oder „6:23“ (wird auf Viertelstunden gerundet)
    Zervixschleim: t, o (= ∅), f, s, s+ bzw. sp, (s), (s+)
    Blutung: x … xxxx bzw. * … **** (Schmierblutung … stark)
    Mittelschmerz: m, l, r · Brustsymptom: b, bs
    Geschlechtsverkehr: gv, ggv (geschützt)
    Ausklammern: a · 1. Zyklustag: zt1
    Notiz: alles nach #
    """

    public static func parse(_ input: String) -> QuickEntryResult {
        var result = QuickEntryResult()
        var text = input
        if let hash = text.firstIndex(of: "#") {
            let note = text[text.index(after: hash)...].trimmingCharacters(in: .whitespaces)
            if !note.isEmpty { result.note = note }
            text = String(text[..<hash])
        }
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }) {
            let token = raw.lowercased()
            if !apply(token: token, to: &result) {
                result.unrecognized.append(String(raw))
            }
        }
        return result
    }

    private static func apply(token: String, to r: inout QuickEntryResult) -> Bool {
        switch token {
        case "t": r.mucus = .symbol(.t); return true
        case "o", "ø", "∅": r.mucus = .symbol(.nothing); return true
        case "f": r.mucus = .symbol(.f); return true
        case "s": r.mucus = .symbol(.s); return true
        case "s+", "sp": r.mucus = .symbol(.sPlus); return true
        case "(s)": r.mucus = .symbol(.s, reduced: true); return true
        case "(s+)", "(sp)": r.mucus = .symbol(.sPlus, reduced: true); return true
        case "m": r.mittelschmerz = .unspecified; return true
        case "l", "ml": r.mittelschmerz = .left; return true
        case "r", "mr": r.mittelschmerz = .right; return true
        case "mb": r.mittelschmerz = .both; return true
        case "b": r.breast = .tension; return true
        case "bs": r.breast = .pain; return true
        case "gv": r.intercourse = .unprotected; return true
        case "ggv": r.intercourse = .protected; return true
        case "a": r.excluded = true; return true
        case "zt1": r.firstCycleDay = true; return true
        default: break
        }
        // Blutung: x … xxxx oder * … ****
        if !token.isEmpty, token.count <= 4, token.allSatisfy({ $0 == "x" }) || token.allSatisfy({ $0 == "*" }) {
            r.bleeding = Bleeding(rawValue: token.count)
            return true
        }
        // Uhrzeit mit Doppelpunkt
        if token.contains(":") {
            let p = token.split(separator: ":")
            if p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) {
                r.time = TemperatureInput.roundToQuarter(h * 60 + m)
                return true
            }
            return false
        }
        // Temperatur mit Komma/Punkt
        if token.contains(",") || token.contains(".") {
            if let t = TemperatureInput.parse(token) { r.temperature = t; return true }
            return false
        }
        guard token.allSatisfy(\.isNumber), let n = Int(token) else { return false }
        switch token.count {
        case 1:
            return false
        case 2:
            // Nur Nachkommastellen: „67“ → 36,67 → 36,65
            r.temperature = TemperatureInput.round(36 + Double(n) / 100)
            return true
        case 3:
            let lead = n / 10
            if (34...42).contains(lead) {
                r.temperature = TemperatureInput.round(Double(n) / 10)
                return true
            }
            let h = n / 100, m = n % 100
            guard (0..<24).contains(h), (0..<60).contains(m) else { return false }
            r.time = TemperatureInput.roundToQuarter(h * 60 + m)
            return true
        case 4:
            let lead = n / 100
            if (34...42).contains(lead) {
                r.temperature = TemperatureInput.round(Double(n) / 100)
                return true
            }
            let h = n / 100, m = n % 100
            guard (0..<24).contains(h), (0..<60).contains(m) else { return false }
            r.time = TemperatureInput.roundToQuarter(h * 60 + m)
            return true
        default:
            return false
        }
    }
}
