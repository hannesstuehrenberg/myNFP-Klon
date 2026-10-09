import SwiftUI
import NFPCore

/// Suche in Notizen, Medikamenten, Zusatzleisten, Störungen und Zykluskommentaren.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let hits = Search.search(query, data: model.data, cycles: model.cycles)
        List {
            if query.isEmpty {
                Text("Durchsucht Notizen, Medikamente, Zusatzleisten, Störungen und Zykluskommentare.")
                    .foregroundStyle(.secondary)
            } else if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(hits) { hit in
                Button {
                    model.chartCycleStart = hit.cycleStart
                    model.selectedDate = hit.date
                    model.selectedTab = .chart
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(hit.date.longGerman).font(.subheadline.weight(.semibold))
                            if let d = hit.cycleDay {
                                Text("ZT \(d)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.accent.opacity(0.2)))
                            }
                            Spacer()
                            Text(hit.field).font(.caption).foregroundStyle(.secondary)
                        }
                        highlighted(hit.text)
                            .font(.subheadline)
                            .lineLimit(3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Suche")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Suchbegriff")
    }

    private func highlighted(_ text: String) -> Text {
        guard !query.isEmpty, let range = text.range(of: query, options: .caseInsensitive) else { return Text(text) }
        var a = AttributedString(text)
        if let r = Range(range, in: a) {
            a[r].backgroundColor = .yellow.opacity(0.5)
            a[r].font = .subheadline.bold()
        }
        return Text(a)
    }
}

/// Tabelle mit allen Notizen je Zyklus
struct NotesTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.cycles.reversed()) { cycle in
                let notes = notesOf(cycle)
                if !notes.isEmpty || !(cycle.meta.comment ?? "").isEmpty {
                    Section("Zyklus \(model.cycleNumber(cycle)) · \(cycle.startDate.german)") {
                        if let c = cycle.meta.comment, !c.isEmpty {
                            Label(c, systemImage: "text.bubble").font(.subheadline)
                        }
                        ForEach(notes) { line in
                            Button {
                                model.chartCycleStart = cycle.startDate
                                model.selectedDate = cycle.date(ofDay: line.day)
                                model.selectedTab = .chart
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("ZT \(line.day)").font(.subheadline.monospacedDigit().bold())
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 52, alignment: .leading)
                                    Text(line.text).font(.subheadline)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notizen")
    }

    struct NoteLine: Identifiable {
        let day: Int
        let text: String
        var id: Int { day }
    }

    private func notesOf(_ c: Cycle) -> [NoteLine] {
        c.entries.enumerated().compactMap { i, e -> NoteLine? in
            guard let e else { return nil }
            var parts: [String] = []
            if let n = e.note, !n.isEmpty { parts.append(n) }
            if let m = e.medication, !m.isEmpty { parts.append("💊 \(m)") }
            return parts.isEmpty ? nil : NoteLine(day: i + 1, text: parts.joined(separator: " · "))
        }
    }
}
