import Foundation

public enum TemperatureInput {
    public static let plausibleRange: ClosedRange<Double> = 34.0...42.0

    /// Rundung auf 0,05 °C wie bei der symptothermalen Methode üblich (36,23 → 36,25; 37,02 → 37,00).
    public static func round(_ value: Double) -> Double {
        let steps = (value * 20 + 1e-9).rounded(.toNearestOrAwayFromZero)
        return steps / 20
    }

    /// Formatierung mit zwei Nachkommastellen und Komma.
    public static func format(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Eingabe im normalen Temperaturfeld: „36,65“, „36.65“, „3665“, „37“ (= 37,00), „370“ (= 37,0).
    public static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        var value: Double?
        if t.contains(".") {
            value = Double(t)
        } else if t.allSatisfy(\.isNumber) {
            switch t.count {
            case 2: value = Double(t)
            case 3: value = Double(t).map { $0 / 10 }
            case 4: value = Double(t).map { $0 / 100 }
            default: value = nil
            }
        }
        guard let v = value, plausibleRange.contains(v) else { return nil }
        return round(v)
    }

    /// Uhrzeit-Formatierung `HH:mm`
    public static func formatTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Rundet eine Uhrzeit auf die nächste Viertelstunde.
    public static func roundToQuarter(_ minutes: Int) -> Int {
        let q = Int((Double(minutes) / 15).rounded()) * 15
        return min(q, 23 * 60 + 45)
    }
}
