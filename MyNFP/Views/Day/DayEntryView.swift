import SwiftUI
import NFPCore

/// Tagesdaten erfassen, bearbeiten oder löschen. Alle Angaben sind optional.
struct DayEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var date: LocalDate
    @State private var entry: DayEntry
    @State private var tempText = ""
    @State private var quickText = ""
    @State private var quickFeedback: String?
    @State private var showDeleteConfirm = false
    @State private var invalidTemperature = false
    @FocusState private var focusedField: Field?

    enum Field { case temperature, quick, note, medication }

    init(date: LocalDate) {
        _date = State(initialValue: date)
        _entry = State(initialValue: DayEntry(date: date))
    }

    private var settings: AppSettings { model.settings }
    private var hidden: Set<CoreRow> { settings.hiddenCoreRows }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                if settings.effectiveQuickEntry { quickEntrySection }
                temperatureSection
                bleedingSection
                if !hidden.contains(.mucus) { mucusSection }
                if !hidden.contains(.cervix) { cervixSection }
                otherSymptomsSection
                notesSection
                barsSection
                if model.data.days[date] != nil {
                    Section {
                        Button("Tagesdaten löschen", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle("Tagesdaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { if commit() { dismiss() } }.bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
                }
            }
            .confirmationDialog("Alle Daten dieses Tages löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    model.deleteEntry(date)
                    dismiss()
                }
            }
            .alert("Ungültige Temperatur", isPresented: $invalidTemperature) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Bitte gib die Temperatur z. B. als 36,55 ein (Bereich 34–42 °C).")
            }
            .onAppear { load(date) }
        }
    }

    // MARK: Abschnitte

    private var headerSection: some View {
        Section {
            HStack {
                Button { switchDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Vorheriger Tag")
                Spacer()
                VStack(spacing: 2) {
                    Text(date.longGerman).font(.headline)
                    if let c = model.cycle(containing: date) {
                        let d = c.cycleDay(of: date)
                        let s = model.evaluation(for: c)?.status(day: d) ?? .unknown
                        Text("ZT \(d) · \(Theme.statusText(s, wantsChild: c.meta.wantsChild))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("kein Zyklus").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { switchDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(date >= model.today)
                    .accessibilityLabel("Nächster Tag")
            }
        }
    }

    private var quickEntrySection: some View {
        Section {
            TextField("z. B. 3667 s+ gv # Notiz", text: $quickText)
                .focused($focusedField, equals: .quick)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(applyQuickEntry)
            Button("Übernehmen", action: applyQuickEntry)
                .disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
            if let quickFeedback {
                Text(quickFeedback).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Schnelleingabe")
        } footer: {
            if !settings.hideHelpTexts { Text(QuickEntryParser.helpText) }
        }
    }

    private var temperatureSection: some View {
        Section {
            HStack {
                Text("Temperatur")
                Spacer()
                TextField("36,50", text: $tempText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .temperature)
                    .frame(width: 90)
                    .onChange(of: focusedField) { old, _ in
                        if old == .temperature { normalizeTemperature() }
                    }
                Text("°C").foregroundStyle(.secondary)
            }
            if !hidden.contains(.time) {
                HStack {
                    if let m = entry.measurementTime {
                        DatePicker("Messuhrzeit", selection: Binding(
                            get: { timeDate(m) },
                            set: { entry.measurementTime = minutes(of: $0) }
                        ), displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                        Button { entry.measurementTime = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Messuhrzeit entfernen")
                    } else {
                        Text("Messuhrzeit")
                        Spacer()
                        Button("Jetzt") { entry.measurementTime = minutes(of: Date()) }
                            .buttonStyle(.bordered)
                        Button("Wählen") { entry.measurementTime = lastMeasurementTime ?? 6 * 60 + 30 }
                            .buttonStyle(.bordered)
                    }
                }
            }
            Toggle("Wert ausklammern (gestört)", isOn: $entry.excluded)
            if !hidden.contains(.disturbances) {
                VStack(alignment: .leading) {
                    Text("Störungen").font(.subheadline).foregroundStyle(.secondary)
                    MultiChipPicker(options: Disturbance.allCases, selection: $entry.disturbances, label: \.label, tint: .orange)
                }
            }
        } header: {
            Text("Temperatur")
        } footer: {
            if !settings.hideHelpTexts {
                Text("Die Temperatur wird beim Speichern auf 0,05 °C gerundet. Klammere nur Werte aus, die nach oben gestört sind – sie werden bei der Auswertung ignoriert und grau dargestellt.")
            }
        }
    }

    private var bleedingSection: some View {
        Section {
            if !hidden.contains(.bleeding) {
                SingleChipPicker(options: Bleeding.allCases, selection: $entry.bleeding, label: \.label, tint: Theme.bleeding)
            }
            Toggle("Ist 1. Zyklustag", isOn: $entry.isFirstCycleDay)
        } header: {
            Text("Blutung")
        } footer: {
            if !settings.hideHelpTexts {
                Text("Der 1. Zyklustag ist der erste Tag einer Blutung in gewohnter Stärke. Auch Zwischen- oder Nachblutungen kannst du hier erfassen.")
            }
        }
    }

    private var mucusBinding: Binding<MucusObservation> {
        Binding(get: { entry.mucus ?? MucusObservation() },
                set: { entry.mucus = $0.isEmpty ? nil : $0 })
    }

    private var mucusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gefühlt / empfunden").font(.subheadline).foregroundStyle(.secondary)
                SingleChipPicker(options: MucusFeeling.allCases, selection: Binding(
                    get: { mucusBinding.wrappedValue.feeling },
                    set: { v in var m = mucusBinding.wrappedValue; m.feeling = v; m.manualSymbol = nil; mucusBinding.wrappedValue = m }
                ), label: \.label)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Gesehen (S)").font(.subheadline).foregroundStyle(.secondary)
                MultiChipPicker(options: MucusAppearance.sCategory, selection: appearanceBinding, label: \.label, tint: Theme.fertile)
                Text("Gesehen (S+)").font(.subheadline).foregroundStyle(.secondary)
                MultiChipPicker(options: MucusAppearance.sPlusCategory, selection: appearanceBinding, label: \.label, tint: Theme.peak)
            }
            HStack {
                Text("Symbol")
                Spacer()
                Text(currentMucusSymbol ?? "–")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.peak)
            }
            if settings.effectiveSubdifferentiation, let s = mucusBinding.wrappedValue.symbol, s == .s || s == .sPlus {
                Toggle("Etwas schlechter als üblich – (\(s.label))", isOn: Binding(
                    get: { mucusBinding.wrappedValue.reduced },
                    set: { v in var m = mucusBinding.wrappedValue; m.reduced = v; mucusBinding.wrappedValue = m }
                ))
            }
        } header: {
            Text("Zervixschleim")
        } footer: {
            if !settings.hideHelpTexts {
                Text("Trage die beste Qualität des Tages ein. Bei mehreren Eigenschaften zählt die fruchtbarste – das Symbol wird automatisch bestimmt.")
            }
        }
    }

    private var appearanceBinding: Binding<Set<MucusAppearance>> {
        Binding(get: { mucusBinding.wrappedValue.appearance },
                set: { v in var m = mucusBinding.wrappedValue; m.appearance = v; m.manualSymbol = nil; mucusBinding.wrappedValue = m })
    }

    private var currentMucusSymbol: String? {
        guard let m = entry.mucus else { return nil }
        return settings.effectiveSubdifferentiation ? m.displaySymbol : m.symbol?.label
    }

    private var cervixBinding: Binding<CervixObservation> {
        Binding(get: { entry.cervix ?? CervixObservation() },
                set: { entry.cervix = $0.isEmpty ? nil : $0 })
    }

    private var cervixSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Position").font(.subheadline).foregroundStyle(.secondary)
                SingleChipPicker(options: CervixPosition.allCases, selection: Binding(
                    get: { cervixBinding.wrappedValue.position },
                    set: { v in var c = cervixBinding.wrappedValue; c.position = v; cervixBinding.wrappedValue = c }), label: \.label)
                Text("Öffnung").font(.subheadline).foregroundStyle(.secondary)
                SingleChipPicker(options: CervixOpening.allCases, selection: Binding(
                    get: { cervixBinding.wrappedValue.opening },
                    set: { v in var c = cervixBinding.wrappedValue; c.opening = v; cervixBinding.wrappedValue = c }), label: { "\($0.symbol) \($0.label)" })
                Text("Härte").font(.subheadline).foregroundStyle(.secondary)
                SingleChipPicker(options: CervixFirmness.allCases, selection: Binding(
                    get: { cervixBinding.wrappedValue.firmness },
                    set: { v in var c = cervixBinding.wrappedValue; c.firmness = v; cervixBinding.wrappedValue = c }), label: \.label)
            }
            if let c = entry.cervix, !c.isEmpty, !c.isComplete {
                Label("Unvollständig: Für die Auswertung werden Öffnung und Härte benötigt.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Muttermund")
        }
    }

    private var otherSymptomsSection: some View {
        Section("Weitere Symptome") {
            if !hidden.contains(.breast) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Brustsymptom").font(.subheadline).foregroundStyle(.secondary)
                    SingleChipPicker(options: BreastSymptom.allCases, selection: $entry.breast, label: { "\($0.symbol) – \($0.label)" })
                }
            }
            if !hidden.contains(.mittelschmerz) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mittelschmerz").font(.subheadline).foregroundStyle(.secondary)
                    SingleChipPicker(options: MittelschmerzSide.allCases, selection: $entry.mittelschmerz, label: \.label)
                }
            }
            if !hidden.contains(.intercourse) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geschlechtsverkehr").font(.subheadline).foregroundStyle(.secondary)
                    SingleChipPicker(options: Intercourse.allCases, selection: $entry.intercourse,
                                     label: { $0 == .unprotected ? "ungeschützt" : "geschützt" }, tint: Theme.fertile)
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notizen") {
            if !hidden.contains(.note) {
                SuggestingTextField(title: "Notiz", text: Binding(get: { entry.note ?? "" }, set: { entry.note = $0.isEmpty ? nil : $0 }),
                                    suggestions: model.suggestions(for: \.note, prefix: entry.note ?? ""))
                    .focused($focusedField, equals: .note)
            }
            if !hidden.contains(.medication) {
                SuggestingTextField(title: "Medikamente", text: Binding(get: { entry.medication ?? "" }, set: { entry.medication = $0.isEmpty ? nil : $0 }),
                                    suggestions: model.suggestions(for: \.medication, prefix: entry.medication ?? ""))
                    .focused($focusedField, equals: .medication)
            }
        }
    }

    @ViewBuilder
    private var barsSection: some View {
        let visible = settings.bars.filter(\.isVisible)
        if !visible.isEmpty {
            Section {
                ForEach(visible) { bar in
                    BarInputView(bar: bar, value: Binding(
                        get: { entry.bars[bar.id] ?? BarValue() },
                        set: { v in entry.bars[bar.id] = v.isEmpty ? nil : v }
                    ))
                }
                Button("Zusatzleisten vom Vortag übernehmen") { copyBarsFromPreviousDay() }
                    .disabled(model.data.days[date.adding(days: -1)]?.bars.isEmpty ?? true)
            } header: {
                Text("Zusatzleisten")
            } footer: {
                if !settings.hideHelpTexts { Text("Welche Leisten angezeigt werden, legst du unter Mehr → Tagesdaten-Einstellungen fest.") }
            }
        }
    }

    // MARK: Logik

    private func load(_ d: LocalDate) {
        date = d
        entry = model.entry(for: d)
        tempText = entry.temperature.map(TemperatureInput.format) ?? ""
        quickText = ""
        quickFeedback = nil
    }

    private func normalizeTemperature() {
        let t = tempText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { entry.temperature = nil; return }
        if let v = TemperatureInput.parse(t) {
            entry.temperature = v
            tempText = TemperatureInput.format(v)
        }
    }

    /// Übernimmt die Eingaben. Gibt false zurück, wenn die Temperatur ungültig ist.
    @discardableResult
    private func commit() -> Bool {
        let t = tempText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            entry.temperature = nil
        } else if let v = TemperatureInput.parse(t) {
            entry.temperature = v
        } else {
            invalidTemperature = true
            return false
        }
        entry.note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        entry.medication = entry.medication?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if entry != model.data.days[date] && (entry.hasData || model.data.days[date] != nil) {
            model.save(entry: entry)
        }
        return true
    }

    private func switchDay(_ delta: Int) {
        guard commit() else { return }
        let next = date.adding(days: delta)
        load(next)
        model.selectedDate = next
        if let c = model.cycle(containing: next) { model.chartCycleStart = c.startDate }
    }

    private func applyQuickEntry() {
        let r = QuickEntryParser.parse(quickText)
        r.apply(to: &entry)
        if let t = r.temperature { tempText = TemperatureInput.format(t) }
        quickFeedback = r.unrecognized.isEmpty ? nil : "Nicht erkannt: \(r.unrecognized.joined(separator: ", "))"
        if r.unrecognized.isEmpty { quickText = "" }
    }

    private func copyBarsFromPreviousDay() {
        guard let prev = model.data.days[date.adding(days: -1)] else { return }
        for (k, v) in prev.bars where entry.bars[k] == nil { entry.bars[k] = v }
    }

    private var lastMeasurementTime: Int? {
        model.data.days.values.filter { $0.date < date && $0.measurementTime != nil }.max { $0.date < $1.date }?.measurementTime
    }

    private func timeDate(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TemperatureInput.roundToQuarter((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Textfeld mit Vorschlägen aus bisherigen Einträgen
struct SuggestingTextField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(1...4)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { s in
                            Chip(title: s, isSelected: false) { text = s }
                        }
                    }
                }
            }
        }
    }
}
