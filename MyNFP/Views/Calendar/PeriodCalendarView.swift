import SwiftUI
import NFPCore

/// Periodenkalender mit realistischer Prognose (berücksichtigt die natürliche Zyklusschwankung).
struct PeriodCalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var monthOffset = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthHeader
                    MonthGrid(month: displayedMonth)
                        .padding(.horizontal, 8)
                        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                            if v.translation.width < -40 { monthOffset += 1 }
                            if v.translation.width > 40 { monthOffset -= 1 }
                        })
                    legend
                    forecastList
                }
                .padding(.vertical)
            }
            .navigationTitle("Periodenkalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Heute") { monthOffset = 0 }
                }
            }
        }
    }

    private var displayedMonth: LocalDate {
        model.today.startOfMonth.adding(months: monthOffset)
    }

    private var monthHeader: some View {
        HStack {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").font(.title3) }
                .accessibilityLabel("Vorheriger Monat")
            Spacer()
            Text(displayedMonth.monthYearGerman).font(.title3.bold())
            Spacer()
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").font(.title3) }
                .accessibilityLabel("Nächster Monat")
        }
        .padding(.horizontal)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(AnyView(Circle().fill(Theme.bleeding)), "Blutung (erfasst)")
            legendRow(AnyView(Circle().stroke(Theme.forecast, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))), "erwartete Periode (Prognose)")
            legendRow(AnyView(Circle().fill(Theme.forecast.opacity(0.18))), "möglicher Periodenbeginn (Schwankungsbereich)")
            legendRow(AnyView(Text("1").font(.caption2.bold()).foregroundStyle(Theme.higherValues)), "1. höhere Messung")
            legendRow(AnyView(RoundedRectangle(cornerRadius: 2).fill(Theme.infertile).frame(height: 4)), "unfruchtbar laut Auswertung")
        }
        .font(.footnote)
        .padding(.horizontal)
    }

    private func legendRow(_ v: AnyView, _ text: String) -> some View {
        HStack(spacing: 8) {
            v.frame(width: 16, height: 16)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var forecastList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nächste Perioden").font(.headline)
            if model.predictions.isEmpty {
                Text("Für eine Prognose wird mindestens ein laufender Zyklus benötigt.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.predictions) { p in
                HStack {
                    VStack(alignment: .leading) {
                        Text("ca. \(p.likelyStart.longGerman)").font(.subheadline.weight(.semibold))
                        Text("zwischen \(p.earliestStart.shortGerman) und \(p.latestStart.shortGerman)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if p.basedOnTemperature {
                        Label("nach Temperatur", systemImage: "thermometer.medium")
                            .font(.caption2).foregroundStyle(Theme.higherValues)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            }
            Text("Die Prognose basiert auf deinen bisherigen Zykluslängen bzw. – nach der 1. höheren Messung – auf deinen Hochlagen. Sie ist keine Aussage über fruchtbare Tage.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}

struct MonthGrid: View {
    @Environment(AppModel.self) private var model
    let month: LocalDate

    var body: some View {
        let first = month.startOfMonth
        let leading = first.isoWeekday - 1
        let days = LocalDate.daysInMonth(year: first.year, month: first.month)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(LocalDate.germanWeekdayShort, id: \.self) { w in
                Text(w).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(Array((-leading)..<0), id: \.self) { _ in Color.clear.frame(height: 44) }
            ForEach(0..<days, id: \.self) { i in
                let date = first.adding(days: i)
                CalendarDayCell(date: date)
                    .onTapGesture {
                        if date <= model.today { model.editingDate = date }
                    }
            }
        }
    }
}

struct CalendarDayCell: View {
    @Environment(AppModel.self) private var model
    let date: LocalDate

    var body: some View {
        let entry = model.data.days[date]
        let isToday = date == model.today
        let cycle = model.cycle(containing: date)
        let ev = cycle.flatMap { model.evaluation(for: $0) }
        let cd = cycle?.cycleDay(of: date)
        let status = (cd.flatMap { ev?.status(day: $0) }) ?? .unknown
        let isFHM = cd != nil && ev?.temperature.firstHigherDay == cd && ev?.temperature.status == .completed
        let forecast = forecastState
        VStack(spacing: 2) {
            ZStack {
                if let b = entry?.bleeding {
                    Circle().fill(Theme.bleeding.opacity(b == .spotting ? 0.45 : 1))
                } else if forecast == .likely {
                    Circle().stroke(Theme.forecast, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                } else if forecast == .possible {
                    Circle().fill(Theme.forecast.opacity(0.18))
                }
                if isToday {
                    Circle().stroke(Theme.accent, lineWidth: 2.5).padding(-2)
                }
                Text("\(date.day)")
                    .font(.system(size: 15, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(entry?.bleeding != nil && entry?.bleeding != .spotting ? Color.white : (date.isWeekend ? Color.red : Color.primary))
            }
            .frame(width: 34, height: 34)
            HStack(spacing: 2) {
                if isFHM {
                    Text("1").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.higherValues)
                }
                if entry?.intercourse != nil {
                    Image(systemName: "heart.fill").font(.system(size: 7)).foregroundStyle(Theme.fertile)
                }
            }
            .frame(height: 8)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(status.isInfertile ? Theme.infertile : Color.clear)
                .frame(height: 3)
        }
        .frame(height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.longGerman)\(entry?.bleeding != nil ? ", Blutung" : "")\(forecast != .none ? ", Periode erwartet" : "")")
    }

    enum ForecastState { case none, possible, likely }

    private var forecastState: ForecastState {
        guard date > model.today else { return .none }
        for p in model.predictions {
            let likelyEnd = p.likelyStart.adding(days: p.bleedingDays - 1)
            if date >= p.likelyStart && date <= likelyEnd { return .likely }
            if date >= p.earliestStart && date <= p.latestStart { return .possible }
        }
        return .none
    }
}
