import SwiftUI
import NFPCore

/// Farben und Formatierungen der App
enum Theme {
    static let accent = Color("AccentColor")

    static let infertile = Color(red: 0.30, green: 0.69, blue: 0.47)       // grün
    static let fertile = Color(red: 0.91, green: 0.36, blue: 0.42)         // rot/rosa
    static let fertileWish = Color(red: 0.25, green: 0.62, blue: 0.85)     // Kinderwunsch: blau = fruchtbar
    static let infertileWish = Color.gray
    static let unknown = Color.gray.opacity(0.35)
    static let bleeding = Color(red: 0.80, green: 0.15, blue: 0.20)
    static let forecast = Color(red: 0.86, green: 0.20, blue: 0.25)
    static let pregnancy = Color(red: 0.55, green: 0.33, blue: 0.80)       // lila Balken
    static let coverline = Color(red: 0.85, green: 0.25, blue: 0.25)
    static let lowValues = Color(red: 0.20, green: 0.45, blue: 0.85)
    static let higherValues = Color(red: 0.85, green: 0.35, blue: 0.20)
    static let peak = Color(red: 0.55, green: 0.33, blue: 0.80)
    static let curve = Color.primary
    static let excluded = Color.gray

    static func statusColor(_ s: DayStatus, wantsChild: Bool) -> Color {
        switch s {
        case .infertileStart, .infertileAfterOvulation:
            return wantsChild ? infertileWish : infertile
        case .fertile, .infertileFromEvening:
            return wantsChild ? fertileWish : fertile
        case .unknown:
            return unknown
        }
    }

    static func statusText(_ s: DayStatus, wantsChild: Bool) -> String {
        if wantsChild {
            switch s {
            case .fertile: return "fruchtbare Zeit – gute Chancen"
            case .infertileFromEvening: return "Auswertung heute Abend abgeschlossen"
            case .infertileStart: return "Zyklusanfang"
            case .infertileAfterOvulation: return "nach dem Eisprung"
            case .unknown: return "noch offen"
            }
        }
        return s.label
    }

    static func sliderColor(_ value: Int, redToGreen: Bool) -> Color {
        let v = Double(max(1, min(5, value)) - 1) / 4
        let t = redToGreen ? v : 1 - v
        return Color(red: 0.9 * (1 - t) + 0.25 * t, green: 0.3 * (1 - t) + 0.7 * t, blue: 0.3)
    }
}

extension LocalDate {
    var longGerman: String {
        "\(weekdayShortGerman), \(german)"
    }

    var monthYearGerman: String {
        "\(LocalDate.germanMonthNames[month - 1]) \(year)"
    }
}

extension Date {
    var germanDateTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }

    var germanRelative: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        return f.localizedString(for: self, relativeTo: Date())
    }
}

extension Double {
    var oneDecimal: String {
        String(format: "%.1f", self).replacingOccurrences(of: ".", with: ",")
    }
}
