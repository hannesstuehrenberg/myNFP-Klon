import SwiftUI
import NFPCore

/// Reiter „Kurve“: das Zyklusblatt
struct ChartScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showDatePicker = false
    @State private var showInfo = false
    @State private var showManual = false
    @State private var showStartCycle = false

    var body: some View {
        NavigationStack {
            Group {
                if let cycle = model.chartCycle {
                    chartContent(cycle)
                } else {
                    emptyState
                }
            }
            .navigationTitle(model.chartCycle.map { "Zyklus \(model.cycleNumber($0))" } ?? "Kurve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDatePicker = true } label: { Image(systemName: "calendar") }
                        .accessibilityLabel("Datum auswählen")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.chartCycle != nil {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(!canStep(-1))
                            .accessibilityLabel("Vorheriger Zyklus")
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(!canStep(1))
                            .accessibilityLabel("Nächster Zyklus")
                    }
                    Button("Heute") {
                        model.chartCycleStart = nil
                        model.selectedDate = model.today
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DateJumpSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showInfo) {
                if let c = model.chartCycle { CycleInfoView(cycle: c) }
            }
            .sheet(isPresented: $showManual) {
                if let c = model.chartCycle { ManualEvaluationView(cycle: c) }
            }
            .sheet(isPresented: $showStartCycle) {
                StartCycleSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Inhalt

    private func chartContent(_ cycle: Cycle) -> some View {
        let ev = model.evaluation(for: cycle)
        let selectedDay = cycle.cycleDay(of: model.selectedDate)
        return ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    CycleHeaderView(cycle: cycle, evaluation: ev)
                        .padding(.horizontal)
                    CycleChartView(cycle: cycle, evaluation: ev, selectedDay: selectedDay) { day in
                        let date = cycle.date(ofDay: day)
                        if date == model.selectedDate {
                            model.editingDate = date
                        } else {
                            model.selectedDate = date
                        }
                    }
                    if let p = ev?.pregnancy {
                        PregnancyInfoView(pregnancy: p, today: model.today, settings: model.settings)
                            .padding(.horizontal)
                    }
                    if let hints = ev?.hints, !hints.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(hints, id: \.self) { h in
                                Label(h, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal)
                    }
                    if selectedDay >= 1 {
                        DaySummaryCard(date: model.selectedDate, cycle: cycle, evaluation: ev)
                            .padding(.horizontal)
                    }
                    if let comment = cycle.meta.comment, !comment.isEmpty {
                        Label(comment, systemImage: "text.bubble")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.top, 8)
            }
            floatingButtons(cycle)
        }
    }

    private func floatingButtons(_ cycle: Cycle) -> some View {
        HStack(spacing: 12) {
            RoundButton(systemImage: "info") { showInfo = true }
                .accessibilityLabel("Zyklusinfos")
            if cycle.meta.useManualEvaluation {
                RoundButton(systemImage: "gearshape") { showManual = true }
                    .accessibilityLabel("Manuelle Auswertung")
            }
            RoundButton(systemImage: "pencil", prominent: true) {
                model.editingDate = model.selectedDate
            }
            .accessibilityLabel("Tagesdaten erfassen")
        }
        .padding()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch kein Zyklus", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Trage den 1. Tag deiner letzten Periode ein, um mit dem Zyklusblatt zu beginnen.")
        } actions: {
            Button("1. Zyklustag eintragen") { showStartCycle = true }
                .buttonStyle(.borderedProminent)
            Button("Demo-Modus ansehen") { model.enterDemo() }
        }
    }

    // MARK: Zyklus wechseln

    private func index(of cycle: Cycle?) -> Int? {
        guard let cycle else { return nil }
        return model.cycles.firstIndex { $0.startDate == cycle.startDate }
    }

    private func canStep(_ delta: Int) -> Bool {
        guard let i = index(of: model.chartCycle) else { return false }
        return model.cycles.indices.contains(i + delta)
    }

    private func step(_ delta: Int) {
        guard let i = index(of: model.chartCycle), model.cycles.indices.contains(i + delta) else { return }
        let target = model.cycles[i + delta]
        model.chartCycleStart = target.startDate
        model.selectedDate = target.contains(model.today) ? model.today : target.startDate
    }
}

// MARK: - Zyklusblatt mit Scrollen und Auswahl

struct CycleChartView: View {
    @Environment(AppModel.self) private var model
    let cycle: Cycle
    let evaluation: CycleEvaluation?
    let selectedDay: Int
    var onTapDay: (Int) -> Void

    var body: some View {
        let ctx = ChartContext(cycle: cycle, evaluation: evaluation, settings: model.settings,
                               tempRange: model.temperatureRange(for: cycle), today: model.today,
                               selectedDay: selectedDay >= 1 ? selectedDay : nil)
        let layout = ChartLayout(context: ctx, bars: model.settings.bars)
        HStack(alignment: .top, spacing: 0) {
            ChartLabelsCanvas(layout: layout)
                .background(Color(.systemBackground))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(1...layout.dayCount, id: \.self) { d in
                                Color.clear.frame(width: layout.colW, height: 1).id(d)
                            }
                        }
                        CycleChartCanvas(ctx: ctx, layout: layout)
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                onTapDay(layout.day(atX: location.x))
                            }
                    }
                }
                .onAppear { scroll(proxy, layout: layout, animated: false) }
                .onChange(of: cycle.startDate) { scroll(proxy, layout: layout, animated: false) }
                .onChange(of: selectedDay) { scroll(proxy, layout: layout, animated: true) }
            }
        }
        .frame(height: layout.totalHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zyklusblatt mit \(cycle.length) Tagen")
    }

    private func scroll(_ proxy: ScrollViewProxy, layout: ChartLayout, animated: Bool) {
        let target = max(1, min(layout.dayCount, selectedDay >= 1 ? selectedDay : cycle.length))
        if animated {
            withAnimation { proxy.scrollTo(target, anchor: .center) }
        } else {
            DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
        }
    }
}

// MARK: - Kopfzeile

struct CycleHeaderView: View {
    @Environment(AppModel.self) private var model
    let cycle: Cycle
    let evaluation: CycleEvaluation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(cycle.startDate.german) – \(cycle.isCompleted ? cycle.endDate.german : "heute")")
                    .font(.subheadline.weight(.semibold))
                Text("\(cycle.length) Tage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if cycle.meta.wantsChild {
                    Image(systemName: "heart.circle.fill").foregroundStyle(Theme.fertileWish)
                        .accessibilityLabel("Kinderwunsch")
                }
                if !(cycle.meta.comment ?? "").isEmpty {
                    Image(systemName: "text.bubble").foregroundStyle(.secondary)
                }
                if cycle.meta.useManualEvaluation {
                    Text("manuell").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                }
            }
            if model.data.catalogs.count > 1 {
                Text("Katalog: \(model.data.catalog(id: cycle.meta.catalogID).name)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !cycle.isCompleted || cycle.contains(model.today) {
                TodayStatusView(cycle: cycle, evaluation: evaluation)
            }
        }
    }
}

struct TodayStatusView: View {
    @Environment(AppModel.self) private var model
    let cycle: Cycle
    let evaluation: CycleEvaluation?

    var body: some View {
        let day = cycle.cycleDay(of: model.today)
        let status = evaluation?.status(day: day) ?? .unknown
        let color = Theme.statusColor(status, wantsChild: cycle.meta.wantsChild)
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("Heute, ZT \(day): \(Theme.statusText(status, wantsChild: cycle.meta.wantsChild))")
                    .font(.subheadline.weight(.semibold))
                if let detail = detailText {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
    }

    private var detailText: String? {
        guard let ev = evaluation else { return nil }
        if let i = ev.infertileFromEveningOfDay {
            return "Unfruchtbar ab dem Abend von ZT \(i)" + (ev.temperature.firstHigherDay.map { " · 1. höhere Messung ZT \($0)" } ?? "")
        }
        if ev.temperature.status == .pending, let f = ev.temperature.firstHigherDay {
            return "1. höhere Messung an ZT \(f) – Auswertung läuft"
        }
        if let f = ev.periodForecast {
            return "Periode erwartet \(f.earliest.shortGerman)–\(f.latest.shortGerman)"
        }
        if ev.startPhase.infertileUntilDay > 0 {
            return "\(ev.startPhase.rule.rawValue): unfruchtbar bis ZT \(ev.startPhase.infertileUntilDay)"
        }
        return nil
    }
}

struct PregnancyInfoView: View {
    let pregnancy: PregnancyInfo
    let today: LocalDate
    let settings: AppSettings

    var body: some View {
        if !(settings.hideDueDate && settings.hidePregnancyWeek) {
            HStack(spacing: 10) {
                Image(systemName: "figure.and.child.holdinghands")
                    .foregroundStyle(Theme.pregnancy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hochlagentag \(pregnancy.highPhaseDay) – Schwangerschaft wahrscheinlich")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        if !settings.hidePregnancyWeek {
                            Text(pregnancy.weekLabel(on: today))
                        }
                        if !settings.hideDueDate {
                            Text("vET \(pregnancy.dueDate.german)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.pregnancy.opacity(0.12)))
        }
    }
}

struct RoundButton: View {
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .foregroundStyle(prominent ? Color.white : Theme.accent)
                .background(Circle().fill(prominent ? Theme.accent : Color(.secondarySystemBackground)))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }
}

// MARK: - Datum wählen

struct DateJumpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: ...Date().addingTimeInterval(86400 * 300), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                let d = LocalDate(date)
                if let c = model.cycle(containing: d) {
                    Section {
                        Button("Zyklusblatt anzeigen (ZT \(c.cycleDay(of: d)))") {
                            model.chartCycleStart = c.startDate
                            model.selectedDate = d
                            dismiss()
                        }
                        Button("Tagesdaten erfassen") {
                            model.chartCycleStart = c.startDate
                            model.selectedDate = d
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.editingDate = d }
                        }
                    }
                } else {
                    Section {
                        Text("Dieses Datum liegt vor dem ersten erfassten Zyklus.")
                            .foregroundStyle(.secondary)
                        Button("Hier einen neuen Zyklus beginnen") {
                            model.startCycle(on: d)
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.editingDate = d }
                        }
                    }
                }
            }
            .navigationTitle("Datum auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
            .onAppear { date = model.selectedDate.date() }
        }
    }
}

struct StartCycleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var bleeding: Bleeding = .medium

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("1. Tag der Periode", selection: $date, in: ...Date(), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                    Picker("Blutung", selection: $bleeding) {
                        ForEach(Bleeding.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("Der 1. Zyklustag ist der erste Tag der Blutung in gewohnter Stärke. Schmierblutungen davor zählen zum alten Zyklus.")
                }
            }
            .navigationTitle("Neuer Zyklus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Beginnen") {
                        model.startCycle(on: LocalDate(date), bleeding: bleeding)
                        dismiss()
                    }
                }
            }
        }
    }
}
