import SwiftUI
import NFPCore

/// Erzeugt das Zyklusblatt als PDF oder PNG (zum Teilen, z. B. mit dem Partner oder der Beraterin).
@MainActor
struct ChartExporter {
    let model: AppModel
    let cycle: Cycle

    private var view: some View {
        let ev = model.evaluation(for: cycle)
        let ctx = ChartContext(cycle: cycle, evaluation: ev, settings: model.settings,
                               tempRange: model.temperatureRange(for: cycle), today: model.today,
                               selectedDay: nil, zoomOverride: 1.0)
        let layout = ChartLayout(context: ctx, bars: model.settings.bars)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zyklus \(model.cycleNumber(cycle)) · \(cycle.startDate.german) – \(cycle.endDate.german) · \(cycle.length) Tage")
                    .font(.headline)
                if let ev {
                    Text(summary(ev)).font(.caption)
                }
                if let c = cycle.meta.comment, !c.isEmpty {
                    Text(c).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ChartLabelsCanvas(layout: layout)
                CycleChartCanvas(ctx: ctx, layout: layout)
            }
            Text("Erstellt am \(LocalDate.today.german) · Auswertung nach den Regeln der symptothermalen Methode – bitte stets selbst prüfen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: layout.labelW + layout.contentWidth + 32, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func summary(_ ev: CycleEvaluation) -> String {
        var parts: [String] = []
        if let f = ev.temperature.firstHigherDay { parts.append("1.hM ZT \(f)") }
        if let c = ev.temperature.coverline { parts.append("Hilfslinie \(TemperatureInput.format(c)) °C") }
        let primary = ev.doubleCheck == .mucus ? ev.mucus : ev.cervix
        if let p = primary.peakDay, primary.status == .completed { parts.append("Höhepunkt ZT \(p)") }
        if ev.startPhase.infertileUntilDay > 0 { parts.append("unfruchtbar bis ZT \(ev.startPhase.infertileUntilDay)") }
        if let i = ev.infertileFromEveningOfDay { parts.append("unfruchtbar ab Abend ZT \(i)") }
        return parts.joined(separator: " · ")
    }

    private var baseName: String { "Zyklus-\(cycle.startDate.isoString)" }

    func pdf() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baseName).pdf")
        let renderer = ImageRenderer(content: view)
        var failed = false
        renderer.render { size, render in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { failed = true; return }
            pdf.beginPDFPage(nil)
            render(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        if failed { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    func png() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baseName).png")
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
