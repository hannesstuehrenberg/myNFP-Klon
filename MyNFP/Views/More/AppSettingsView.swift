import SwiftUI
import NFPCore

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] },
                set: { v in model.updateSettings { $0[keyPath: keyPath] = v } })
    }

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: binding(\.appearance)) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Zoom Zyklusblatt")
                        Spacer()
                        Text("\(model.settings.zoomPercent) %").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(model.settings.zoomPercent) },
                                          set: { v in model.updateSettings { $0.zoomPercent = Int(v) } }),
                           in: 60...200, step: 5)
                    Button("Standard (115 %)") { model.updateSettings { $0.zoomPercent = 115 } }
                        .font(.footnote)
                }
                Toggle("Relevante Temperaturwerte hervorheben", isOn: binding(\.highlightRelevantTemperatures))
            }

            Section {
                Toggle("Lila Balken ausblenden", isOn: binding(\.hidePregnancyBar))
                Toggle("Voraussichtl. Entbindungstermin ausblenden", isOn: binding(\.hideDueDate))
                Toggle("Schwangerschaftswoche ausblenden", isOn: binding(\.hidePregnancyWeek))
            } header: {
                Text("Schwangerschaft")
            } footer: {
                Text("Ab Hochlagentag 19 zeigt das Zyklusblatt einen lila Balken, den voraussichtlichen Entbindungstermin (vET) und die Schwangerschaftswoche (SSW).")
            }

            Section {
                Picker("Doppelkontrolle mit", selection: binding(\.doubleCheck)) {
                    ForEach(DoubleCheckSymptom.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Auswertung")
            } footer: {
                Text("Der Muttermund kann als Alternative zum Zervixschleim verwendet werden, falls die Schleimbeobachtung nach mehreren Zyklen nicht gut gelingt. Blende dafür die Zeile „Muttermund“ in den Tagesdaten-Einstellungen ein.")
            }

            Section {
                Toggle("Fortgeschrittenen-Modus", isOn: binding(\.advancedMode))
                if model.settings.advancedMode {
                    Toggle("Laxe Auswertung", isOn: binding(\.laxEvaluation))
                    Toggle("Binnendifferenzierung (S) / (S+)", isOn: binding(\.mucusSubdifferentiation))
                    Toggle("Schnelleingabe", isOn: binding(\.quickEntryEnabled))
                    Toggle("Zyklusanfang nach Muttermund auswerten", isOn: binding(\.cycleStartByCervix))
                    Toggle("Hilfetexte ausblenden", isOn: binding(\.hideHelpTexts))
                }
            } header: {
                Text("Fortgeschrittenen-Modus")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Streng (Standard): Vom möglichen Höhepunkt bis zum Abschluss der Temperaturauswertung wird an jedem Tag ein Schleim- bzw. Muttermund-Eintrag benötigt.")
                    Text("Lax: Ein Tag ohne Eintrag zählt wie ein Tag mit der schlechtesten Qualität. Passt, wenn du bessere Qualität immer einträgst und Tage nur leer lässt, wenn du nichts Besseres beobachtet hast.")
                    Text("In beiden Fällen beginnt die unfruchtbare Zeit nach dem Eisprung erst, wenn auch die Temperaturauswertung abgeschlossen ist.")
                }
            }
        }
        .navigationTitle("App-Einstellungen")
    }
}
