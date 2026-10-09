import SwiftUI
import NFPCore

/// „Wie wurde ausgewertet?“ – Zyklusinfos mit Auswertungsprotokoll, Farblegende und Export.
struct CycleInfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cycle: Cycle

    @State private var pdfURL: URL?
    @State private var imageURL: URL?
    @State private var exportError: String?

    var body: some View {
        let ev = model.evaluation(for: cycle)
        NavigationStack {
            List {
                Section("Überblick") {
                    LabeledContent("Zyklus", value: "\(model.cycleNumber(cycle)) · \(cycle.startDate.german)")
                    LabeledContent("Länge", value: "\(cycle.length) Tage\(cycle.isCompleted ? "" : " (läuft)")")
                    LabeledContent("Katalog", value: model.data.catalog(id: cycle.meta.catalogID).name)
                    if let ev {
                        LabeledContent("Auswertung", value: ev.isManual ? "manuell" : (ev.isLax ? "automatisch (lax)" : "automatisch (streng)"))
                        LabeledContent("Doppelkontrolle mit", value: ev.doubleCheck.label)
                        if let f = ev.temperature.firstHigherDay {
                            LabeledContent("1. höhere Messung", value: "ZT \(f)\(ev.isEarliestFirstHigher ? " (früheste)" : "")")
                        }
                        if let cl = ev.temperature.coverline {
                            LabeledContent("Hilfslinie", value: "\(TemperatureInput.format(cl)) °C")
                        }
                        if let r = ev.temperature.rule, ev.temperature.status == .completed {
                            LabeledContent("Temperaturregel", value: r.rawValue)
                        }
                        let primary = ev.doubleCheck == .mucus ? ev.mucus : ev.cervix
                        if let p = primary.peakDay, primary.status == .completed {
                            LabeledContent("Höhepunkt", value: "ZT \(p)")
                        }
                        LabeledContent("Unfruchtbar am Anfang", value: ev.startPhase.infertileUntilDay > 0
                                       ? "bis ZT \(ev.startPhase.infertileUntilDay) (\(ev.startPhase.rule.rawValue))" : "keine Tage")
                        LabeledContent("Unfruchtbar nach Eisprung", value: ev.infertileFromEveningOfDay.map { "ab Abend ZT \($0)" } ?? "noch offen")
                        if let h = ev.highPhaseLength { LabeledContent("Hochlage", value: "\(h) Tage") }
                        if let f = ev.periodForecast {
                            LabeledContent("Periodenprognose", value: "\(f.earliest.shortGerman) – \(f.latest.shortGerman)")
                        }
                        if let p = ev.pregnancy {
                            LabeledContent("Voraussichtl. Entbindung", value: p.dueDate.german)
                            LabeledContent("Schwangerschaftswoche", value: p.weekLabel(on: model.today))
                        }
                    }
                }

                if let ev {
                    Section {
                        ForEach(ev.log) { entry in
                            ProtocolRow(entry: entry)
                        }
                    } header: {
                        Text("Wie wurde ausgewertet?")
                    } footer: {
                        Text("Wenn du die Auswertung nicht nachvollziehen kannst, sind die Daten nach den Methodenregeln meist nicht auswertbar. Lies die Regeln im Wissensteil nach und prüfe die Auswertung stets selbst auf Plausibilität.")
                    }
                }

                Section("Farben & Symbole") {
                    LegendContent(wantsChild: cycle.meta.wantsChild)
                }

                Section("Exportieren & Teilen") {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Zyklusblatt als PDF teilen", systemImage: "doc.richtext") }
                    }
                    if let imageURL {
                        ShareLink(item: imageURL) { Label("Zyklusblatt als Bild teilen", systemImage: "photo") }
                    }
                    if let exportError {
                        Text(exportError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Zyklusinfos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .task { prepareExports() }
        }
    }

    @MainActor
    private func prepareExports() {
        do {
            let exporter = ChartExporter(model: model, cycle: cycle)
            pdfURL = try exporter.pdf()
            imageURL = try exporter.png()
        } catch {
            exportError = "Export nicht möglich: \(error.localizedDescription)"
        }
    }
}

struct ProtocolRow: View {
    let entry: ProtocolEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            Text(entry.text).font(.subheadline)
        }
    }

    private var icon: String {
        switch entry.kind {
        case .info: return "info.circle"
        case .rule: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .result: return "flag.checkered"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .info: return .secondary
        case .rule: return Theme.infertile
        case .warning: return .orange
        case .result: return Theme.accent
        }
    }
}

struct LegendContent: View {
    var wantsChild = false

    var body: some View {
        Group {
            legendRow(Theme.statusColor(.infertileStart, wantsChild: wantsChild),
                      wantsChild ? "Zyklusanfang / nach dem Eisprung (Kinderwunsch)" : "unfruchtbar (Zyklusanfang bzw. nach dem Eisprung)")
            legendRow(Theme.statusColor(.fertile, wantsChild: wantsChild),
                      wantsChild ? "fruchtbare Zeit (Kinderwunsch)" : "fruchtbar")
            HStack {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.statusColor(.fertile, wantsChild: wantsChild))
                    Rectangle().fill(Theme.statusColor(.infertileAfterOvulation, wantsChild: wantsChild))
                }
                .frame(width: 22, height: 10)
                Text("ab abends unfruchtbar (Abschluss der Doppelkontrolle)")
            }
            legendRow(Theme.forecast, "roter Balken: Periodenprognose (ab der 1. höheren Messung)")
            legendRow(Theme.pregnancy, "lila Balken: Schwangerschaft wahrscheinlich (ab Hochlagentag 19)")
            HStack {
                Circle().stroke(Theme.lowValues, lineWidth: 1.5).frame(width: 12, height: 12).frame(width: 22)
                Text("die 6 niedrigen Werte")
            }
            HStack {
                Circle().stroke(Theme.higherValues, lineWidth: 1.5).frame(width: 12, height: 12).frame(width: 22)
                Text("höhere Messungen (nummeriert)")
            }
            HStack {
                Rectangle().fill(Theme.coverline).frame(width: 22, height: 2)
                Text("Hilfslinie")
            }
            HStack {
                Circle().stroke(Theme.excluded, lineWidth: 1.2).frame(width: 10, height: 10).frame(width: 22)
                Text("ausgeklammerter Wert (grau)")
            }
            HStack {
                Text("HP").font(.caption.bold()).foregroundStyle(.white).padding(2).background(RoundedRectangle(cornerRadius: 3).fill(Theme.peak)).frame(width: 22)
                Text("Höhepunkt, danach 1–3: Tage nach dem Höhepunkt")
            }
            HStack {
                Text("t ∅ f S S+").font(.caption.bold()).frame(width: 70, alignment: .leading)
                Text("Zervixschleim (schlechter → besser)")
            }
            HStack {
                Text("● ◐ ○ H W").font(.caption.bold()).frame(width: 70, alignment: .leading)
                Text("Muttermund: geschlossen/leicht/geöffnet, hart/weich")
            }
        }
        .font(.subheadline)
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 22, height: 10)
            Text(text)
        }
    }
}
