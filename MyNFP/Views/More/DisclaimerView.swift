import SwiftUI

/// Zweckbestimmung und Vorsichtshinweise – beim ersten Start zu bestätigen.
struct DisclaimerView: View {
    @Environment(AppModel.self) private var model
    let showsAccept: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsAccept {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Text("Willkommen")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity)
                }
                Group {
                    Text("Wozu dient die App?").font(.headline)
                    Text("Die App unterstützt Anwenderinnen der symptothermalen Methode bei der Protokollierung und Auswertung ihrer Zyklen. Sie erstellt aus deinen Daten ein Zyklusblatt und wertet es nach dem Sensiplan-Regelwerk aus. Dabei zeigt sie transparent, welche Regeln angewendet werden, damit du die Auswertung nachvollziehen und gegebenenfalls manuell ändern kannst.")
                    Text("Wichtige Hinweise").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Dies ist ein privater Nachbau und **kein zertifiziertes Medizinprodukt**. Prüfe jede Auswertung selbst auf Plausibilität.")
                        bullet("Die App ist **kein Verhütungsmittel**. Die symptothermale Methode erfordert in der fruchtbaren Phase zusätzliche Verhütungsmittel, wenn keine Schwangerschaft gewünscht ist.")
                        bullet("Nicht verwenden bei hormoneller Verhütung oder hormonell wirksamen Medikamenten.")
                        bullet("Nicht verwenden, wenn eine Schwangerschaft zu erhöhten gesundheitlichen Risiken führt.")
                        bullet("Voraussetzung ist die Kenntnis der Methode (z. B. „Natürlich & Sicher“, TRIAS Verlag) und ein Thermometer mit mindestens 0,05 °C Auflösung.")
                        bullet("Die Informationen sind nicht für diagnostische oder therapeutische Zwecke bestimmt.")
                    }
                    Text("Datenschutz").font(.headline)
                    Text("Alle Daten bleiben auf deinem iPhone (verschlüsselt durch den iOS-Datenschutz). Es gibt kein Konto, keinen Server, kein Tracking. Backups landen nur dort, wo du sie selbst hinlegst – auf Wunsch verschlüsselt.")
                }
                if showsAccept {
                    Button {
                        model.updateSettings { $0.acceptedDisclaimer = true }
                    } label: {
                        Text("Verstanden").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top)
                    Button("Erst einmal den Demo-Modus ansehen") {
                        model.updateSettings { $0.acceptedDisclaimer = true }
                        model.enterDemo()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle(showsAccept ? "" : "Zweckbestimmung")
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text((try? AttributedString(markdown: s)) ?? AttributedString(s))
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–")
            }
            Section("Über diese App") {
                Text("Ein privater Nachbau einer NFP-Zyklus-App für die symptothermale Methode nach Sensiplan – komplett offline, ohne Konto und ohne Tracking.")
                Text("„Sensiplan“ ist eine Marke der Malteser Arbeitsgruppe NFP. Diese App steht in keiner Verbindung zur myNFP GmbH oder zur Arbeitsgruppe NFP.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Mehr über die Methode") {
                Link("sensiplan.de – Beraterinnen & Kurse", destination: URL(string: "https://www.sensiplan.de")!)
            }
        }
        .navigationTitle("Über")
    }
}
