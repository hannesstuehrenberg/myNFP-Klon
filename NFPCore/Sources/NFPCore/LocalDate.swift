import Foundation

/// Ein Kalendertag ohne Uhrzeit und Zeitzone.
///
/// Intern als fortlaufende Tagesnummer (Tage seit 1970-01-01) gespeichert,
/// damit Differenzen und Vergleiche trivial und zeitzonenunabhängig sind.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let dayNumber: Int

    public init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    public init(year: Int, month: Int, day: Int) {
        self.dayNumber = LocalDate.daysFromCivil(year: year, month: month, day: day)
    }

    /// Kalendertag eines Zeitpunkts in der aktuellen (oder angegebenen) Zeitzone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public static var today: LocalDate { LocalDate(Date()) }

    public var components: (year: Int, month: Int, day: Int) {
        LocalDate.civilFromDays(dayNumber)
    }

    public var year: Int { components.year }
    public var month: Int { components.month }
    public var day: Int { components.day }

    /// 1 = Montag … 7 = Sonntag (ISO 8601)
    public var isoWeekday: Int {
        // 1970-01-01 war ein Donnerstag (ISO 4)
        let w = ((dayNumber % 7) + 7 + 3) % 7 // 0 = Montag
        return w + 1
    }

    public var isWeekend: Bool { isoWeekday >= 6 }

    public func adding(days: Int) -> LocalDate { LocalDate(dayNumber: dayNumber + days) }

    public func days(until other: LocalDate) -> Int { other.dayNumber - dayNumber }

    public func adding(months: Int) -> LocalDate {
        var (y, m, d) = components
        let total = (y * 12 + (m - 1)) + months
        y = total / 12
        m = total % 12 + 1
        d = min(d, LocalDate.daysInMonth(year: y, month: m))
        return LocalDate(year: y, month: m, day: d)
    }

    public var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        }
    }

    /// Mittag dieses Tages als `Date` (robust gegenüber Sommerzeitwechseln).
    public func date(calendar: Calendar = .current) -> Date {
        let (y, m, d) = components
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: Formatierung

    /// ISO-Format `yyyy-MM-dd` (Speicherformat)
    public var isoString: String {
        let (y, m, d) = components
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...LocalDate.daysInMonth(year: y, month: m)).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Deutsches Kurzformat `dd.MM.`
    public var shortGerman: String {
        let (_, m, d) = components
        return String(format: "%02d.%02d.", d, m)
    }

    /// Deutsches Format `dd.MM.yyyy`
    public var german: String {
        let (y, m, d) = components
        return String(format: "%02d.%02d.%04d", d, m, y)
    }

    public static let germanWeekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    public static let germanMonthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                                          "Juli", "August", "September", "Oktober", "November", "Dezember"]

    public var weekdayShortGerman: String { LocalDate.germanWeekdayShort[isoWeekday - 1] }

    public var description: String { isoString }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.dayNumber < rhs.dayNumber }

    // MARK: Codable als ISO-String

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = LocalDate(isoString: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Ungültiges Datum: \(s)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(isoString)
    }

    // MARK: Algorithmen nach Howard Hinnant (proleptischer gregorianischer Kalender)

    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

extension LocalDate: Identifiable {
    public var id: Int { dayNumber }
}

extension LocalDate: Strideable {
    public func distance(to other: LocalDate) -> Int { other.dayNumber - dayNumber }
    public func advanced(by n: Int) -> LocalDate { adding(days: n) }
}
