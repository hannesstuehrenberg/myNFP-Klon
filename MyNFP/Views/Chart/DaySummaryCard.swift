import SwiftUI
import NFPCore

/// Details des ausgewählten Tages unter dem Zyklusblatt (ersetzt die Tooltips).
struct DaySummaryCard: View {
    @Environment(AppModel.self) private var model
    let date: LocalDate
    let cycle: Cycle
    let evaluation: CycleEvaluation?

    var body: some View {
        let day = cycle.cycleDay(of: date)
        let entry = model.data.days[date]
        let status = evaluation?.status(day: day) ?? .unknown
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(date.longGerman) · ZT \(day)")
                    .font(.headline)
                Spacer()
                Button {
                    model.editingDate = date
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.statusColor(status, wantsChild: cycle.meta.wantsChild)).frame(width: 9, height: 9)
                Text(Theme.statusText(status, wantsChild: cycle.meta.wantsChild))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let e = entry, e.hasData {
                let lines = Self.describe(e, settings: model.settings)
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.element.0).font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(item.element.1).font(.subheadline)
                    }
                }
            } else {
                Text("Keine Daten für diesen Tag. Tippe erneut auf die Spalte oder auf den Stift, um Daten zu erfassen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    static func describe(_ e: DayEntry, settings: AppSettings) -> [(String, String)] {
        var lines: [(String, String)] = []
        if let t = e.temperature {
            var s = "\(TemperatureInput.format(t)) °C"
            if let m = e.measurementTime { s += " um \(TemperatureInput.formatTime(m))" }
            if e.excluded { s += " (ausgeklammert)" }
            lines.append(("Temperatur", s))
        } else if let m = e.measurementTime {
            lines.append(("Messuhrzeit", TemperatureInput.formatTime(m)))
        }
        if !e.disturbances.isEmpty {
            lines.append(("Störungen", e.disturbances.map(\.label).sorted().joined(separator: ", ")))
        }
        if let b = e.bleeding {
            lines.append(("Blutung", b.label + (e.isFirstCycleDay ? " · 1. Zyklustag" : "")))
        } else if e.isFirstCycleDay {
            lines.append(("Zyklus", "1. Zyklustag"))
        }
        if let m = e.mucus, let sym = settings.effectiveSubdifferentiation ? m.displaySymbol : m.symbol?.label {
            var parts: [String] = []
            if let f = m.feeling { parts.append("gefühlt: \(f.label)") }
            if !m.appearance.isEmpty { parts.append("gesehen: \(m.appearance.map(\.label).sorted().joined(separator: ", "))") }
            lines.append(("Zervixschleim", sym + (parts.isEmpty ? "" : " – " + parts.joined(separator: "; "))))
        }
        if let c = e.cervix, !c.isEmpty {
            let parts = [c.position?.label, c.opening?.label, c.firmness?.label].compactMap { $0 }
            lines.append(("Muttermund", parts.joined(separator: ", ")))
        }
        if let b = e.breast { lines.append(("Brustsymptom", b.label)) }
        if let m = e.mittelschmerz { lines.append(("Mittelschmerz", m.label)) }
        if let i = e.intercourse { lines.append(("GV", i.label)) }
        if let n = e.note, !n.isEmpty { lines.append(("Notiz", n)) }
        if let m = e.medication, !m.isEmpty { lines.append(("Medikamente", m)) }
        for bar in settings.bars {
            guard let v = e.bars[bar.id], !v.isEmpty else { continue }
            lines.append((bar.name, DataExporter.barText(v, kind: bar.kind)))
        }
        return lines
    }
}
