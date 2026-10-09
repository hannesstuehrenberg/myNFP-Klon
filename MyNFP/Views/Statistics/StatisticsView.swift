import SwiftUI
import Charts
import NFPCore

/// Reiter „Statistik“: Zykluslängen, Hochlagen, früheste 1. höhere Messung …
struct StatisticsView: View {
    @Environment(AppModel.self) private var model
    @State private var catalogFilter: UUID?

    var body: some View {
        NavigationStack {
            let rows = filteredRows
            let summary = Statistics.summary(rows)
            List {
                if model.data.catalogs.count > 1 {
                    Picker("Katalog", selection: $catalogFilter) {
                        Text("Alle Kataloge").tag(UUID?.none)
                        ForEach(model.data.catalogs) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section("Überblick") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "Zyklen", value: "\(summary.cycleCount)", detail: "\(summary.completedCount) abgeschlossen")
                        StatTile(title: "Ø Zykluslänge", value: summary.averageLength.map { $0.oneDecimal } ?? "–",
                                 detail: range(summary.shortest, summary.longest, unit: "Tage"))
                        StatTile(title: "Ø Hochlage", value: summary.averageHighPhase.map { $0.oneDecimal } ?? "–",
                                 detail: range(summary.shortestHighPhase, summary.longestHighPhase, unit: "Tage"))
                        StatTile(title: "Früheste 1.hM", value: summary.earliestFirstHigher.map { "ZT \($0)" } ?? "–",
                                 detail: summary.averageFirstHigher.map { "Ø ZT \($0.oneDecimal)" } ?? "")
                        StatTile(title: "Ø Blutungstage", value: summary.averageBleedingDays.map { $0.oneDecimal } ?? "–", detail: "")
                        StatTile(title: "Zyklen mit 1.hM", value: "\(summary.cyclesWithFirstHigher)", detail: "für die Minus-8-Regel")
                    }
                    .padding(.vertical, 4)
                }

                let completed = rows.filter(\.isCompleted)
                if completed.count >= 2 {
                    Section("Zykluslänge & Hochlage") {
                        Chart {
                            ForEach(completed) { r in
                                BarMark(x: .value("Beginn", r.start.date()), y: .value("Länge", r.length))
                                    .foregroundStyle(Theme.accent.opacity(0.7))
                                if let h = r.highPhaseLength {
                                    BarMark(x: .value("Beginn", r.start.date()), y: .value("Hochlage", h))
                                        .foregroundStyle(Theme.higherValues.opacity(0.8))
                                }
                            }
                            if let avg = summary.averageLength {
                                RuleMark(y: .value("Ø", avg))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartYAxisLabel("Tage")
                        .frame(height: 200)
                        HStack(spacing: 16) {
                            Label("Zykluslänge", systemImage: "square.fill").foregroundStyle(Theme.accent.opacity(0.7))
                            Label("Hochlage", systemImage: "square.fill").foregroundStyle(Theme.higherValues.opacity(0.8))
                        }
                        .font(.caption)
                    }
                    Section("1. höhere Messung (Zyklustag)") {
                        Chart {
                            ForEach(rows.filter { $0.firstHigherDay != nil }) { r in
                                PointMark(x: .value("Beginn", r.start.date()), y: .value("ZT", r.firstHigherDay!))
                                    .foregroundStyle(r.isEarliestFirstHigher ? Theme.higherValues : Theme.accent)
                            }
                        }
                        .frame(height: 160)
                    }
                }

                Section("Alle Zyklen") {
                    ForEach(rows.reversed()) { r in
                        Button {
                            model.chartCycleStart = r.start
                            model.selectedDate = r.start
                            model.selectedTab = .chart
                        } label: {
                            StatRowView(row: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Statistik")
        }
    }

    private var filteredRows: [CycleStatRow] {
        let all = Statistics.rows(cycles: model.cycles, evaluations: model.evaluations, data: model.data)
        guard let f = catalogFilter else { return all }
        let name = model.data.catalog(id: f).name
        return all.filter { $0.catalogName == name }
    }

    private func range(_ a: Int?, _ b: Int?, unit: String) -> String {
        guard let a, let b else { return "" }
        return "\(a)–\(b) \(unit)"
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
    }
}

struct StatRowView: View {
    let row: CycleStatRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.start.german).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(row.length) Tage\(row.isCompleted ? "" : " (läuft)")").font(.subheadline)
            }
            HStack(spacing: 12) {
                if let f = row.firstHigherDay {
                    Text("1.hM \(f)\(row.isEarliestFirstHigher ? " ★" : "")")
                }
                if let p = row.mucusPeakDay { Text("HP \(p)") }
                if let p = row.cervixPeakDay { Text("MM \(p)") }
                if let h = row.highPhaseLength { Text("Hochlage \(h)") }
                if row.infertileStartUntil > 0 { Text("unfr. bis \(row.infertileStartUntil)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
