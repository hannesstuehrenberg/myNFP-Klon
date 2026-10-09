import SwiftUI
import NFPCore

/// Manuelle Auswertung eines Zyklus: die wichtigsten Phasen selbst markieren.
struct ManualEvaluationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cycle: Cycle

    @State private var manual = ManualEvaluation()
    @State private var coverlineText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("myNFP wertet diesen Zyklus nicht automatisch aus, sondern verwendet deine Angaben. Die automatische Auswertung dient hier nur als Vorschlag.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Vorschlag der automatischen Auswertung übernehmen") { applyAutomatic() }
                }
                Section("Zyklusanfang") {
                    OptionalDayField(title: "Unfruchtbar bis ZT", value: $manual.infertileStartUntilDay, range: 0...max(1, cycle.length))
                }
                Section("Temperatur") {
                    OptionalDayField(title: "1. höhere Messung", value: $manual.firstHigherDay, range: 1...max(1, cycle.length))
                    HStack {
                        Text("Hilfslinie (°C)")
                        Spacer()
                        TextField("z. B. 36,50", text: $coverlineText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                }
                Section("Höhepunkt") {
                    OptionalDayField(title: "Schleim-Höhepunkt", value: $manual.mucusPeakDay, range: 1...max(1, cycle.length))
                    OptionalDayField(title: "Muttermund-Höhepunkt", value: $manual.cervixPeakDay, range: 1...max(1, cycle.length))
                }
                Section {
                    OptionalDayField(title: "Unfruchtbar ab Abend ZT", value: $manual.infertileFromEveningOfDay, range: 1...max(1, cycle.length))
                } header: {
                    Text("Nach dem Eisprung")
                } footer: {
                    Text("Nach der Doppelkontrolle: am Abend des Tages, an dem die zuletzt abgeschlossene Auswertung (Temperatur oder Höhepunkt) endet.")
                }
            }
            .navigationTitle("Manuelle Auswertung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        manual.coverline = TemperatureInput.parse(coverlineText)
                        let value = manual
                        model.updateMeta(for: cycle) { $0.manual = value }
                        dismiss()
                    }
                }
            }
            .onAppear {
                manual = cycle.meta.manual
                coverlineText = manual.coverline.map(TemperatureInput.format) ?? ""
            }
        }
    }

    private func applyAutomatic() {
        // Automatische Auswertung ohne „manuell“-Flag berechnen
        var meta = cycle.meta
        meta.useManualEvaluation = false
        let c = Cycle(startDate: cycle.startDate, endDate: cycle.endDate, isCompleted: cycle.isCompleted, meta: meta, entries: cycle.entries)
        var cycles = model.cycles
        if let i = cycles.firstIndex(where: { $0.startDate == c.startDate }) { cycles[i] = c }
        guard let ev = CycleEvaluator.evaluateAll(cycles: cycles, data: model.data, today: model.today)[c.startDate] else { return }
        manual.infertileStartUntilDay = ev.startPhase.infertileUntilDay
        manual.firstHigherDay = ev.temperature.firstHigherDay
        manual.coverline = ev.temperature.coverline
        manual.mucusPeakDay = ev.mucus.status == .completed ? ev.mucus.peakDay : nil
        manual.cervixPeakDay = ev.cervix.status == .completed ? ev.cervix.peakDay : nil
        manual.infertileFromEveningOfDay = ev.infertileFromEveningOfDay
        coverlineText = manual.coverline.map(TemperatureInput.format) ?? ""
    }
}

struct OptionalDayField: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>

    var body: some View {
        Toggle(isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? range.lowerBound) : nil })) {
            Text(title)
        }
        if let v = value {
            Stepper(value: Binding(get: { v }, set: { value = $0 }), in: range) {
                Text("ZT \(v)").monospacedDigit()
            }
        }
    }
}
