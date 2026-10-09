import Foundation

/// Export aller Daten als ZIP mit CSV-Dateien (UTF-8) und einer JSON-Datei für den Re-Import.
public enum DataExporter {
    public static func csvEscape(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains(",") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func row(_ fields: [String]) -> String { fields.map(csvEscape).joined(separator: ";") }

    public static func dayCSV(data: AppData, cycles: [Cycle], evaluations: [LocalDate: CycleEvaluation]) -> String {
        let bars = data.settings.bars
        var lines: [String] = []
        var header = ["Datum", "Wochentag", "Zyklusbeginn", "Zyklustag", "Status", "Temperatur", "Messuhrzeit",
                      "ausgeklammert", "Störungen", "Blutung", "1. Zyklustag", "Schleim gefühlt", "Schleim gesehen",
                      "Schleim Symbol", "Muttermund Position", "Muttermund Öffnung", "Muttermund Härte",
                      "Brustsymptom", "Mittelschmerz", "Geschlechtsverkehr", "Notiz", "Medikamente"]
        header += bars.map(\.name)
        lines.append(row(header))

        for entry in data.days.values.sorted(by: { $0.date < $1.date }) {
            let c = CycleBuilder.cycle(containing: entry.date, in: cycles)
            let cd = c.map { $0.cycleDay(of: entry.date) }
            let status = c.flatMap { evaluations[$0.startDate] }.map { ev in ev.status(day: cd ?? 0).label } ?? ""
            var f: [String] = [
                entry.date.german,
                entry.date.weekdayShortGerman,
                c?.startDate.german ?? "",
                cd.map(String.init) ?? "",
                status,
                entry.temperature.map(TemperatureInput.format) ?? "",
                entry.measurementTime.map(TemperatureInput.formatTime) ?? "",
                entry.excluded ? "ja" : "",
                entry.disturbances.map(\.label).sorted().joined(separator: ", "),
                entry.bleeding?.label ?? "",
                entry.isFirstCycleDay ? "ja" : "",
                entry.mucus?.feeling?.label ?? "",
                entry.mucus?.appearance.map(\.label).sorted().joined(separator: ", ") ?? "",
                entry.mucus?.displaySymbol ?? "",
                entry.cervix?.position?.label ?? "",
                entry.cervix?.opening?.label ?? "",
                entry.cervix?.firmness?.label ?? "",
                entry.breast?.label ?? "",
                entry.mittelschmerz?.label ?? "",
                entry.intercourse?.label ?? "",
                entry.note ?? "",
                entry.medication ?? "",
            ]
            for bar in bars {
                f.append(barText(entry.bars[bar.id], kind: bar.kind))
            }
            lines.append(row(f))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func barText(_ v: BarValue?, kind: BarKind) -> String {
        guard let v, !v.isEmpty else { return "" }
        if let flag = v.flag { return flag ? "ja" : "nein" }
        if let n = v.number { return String(n) }
        var parts = v.selections
        if let t = v.text, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: ", ")
    }

    public static func cycleCSV(rows: [CycleStatRow]) -> String {
        var lines = [row(["Zyklusbeginn", "Zyklusende", "Länge", "abgeschlossen", "Katalog", "1. höhere Messung (ZT)",
                          "früheste 1.hM", "Schleim-Höhepunkt (ZT)", "Muttermund-Höhepunkt (ZT)", "Hochlage (Tage)",
                          "unfruchtbar am Anfang bis ZT", "Regel Zyklusanfang", "unfruchtbar ab Abend ZT",
                          "Kinderwunsch", "Blutungstage"])]
        for r in rows {
            lines.append(row([
                r.start.german, r.end.german, String(r.length), r.isCompleted ? "ja" : "nein", r.catalogName,
                r.firstHigherDay.map(String.init) ?? "", r.isEarliestFirstHigher ? "ja" : "",
                r.mucusPeakDay.map(String.init) ?? "", r.cervixPeakDay.map(String.init) ?? "",
                r.highPhaseLength.map(String.init) ?? "", String(r.infertileStartUntil), r.startRule.rawValue,
                r.infertileFromEvening.map(String.init) ?? "", r.wantsChild ? "ja" : "", String(r.bleedingDays),
            ]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func cycleMetaCSV(cycles: [Cycle], data: AppData) -> String {
        var lines = [row(["Zyklusbeginn", "Katalog", "Messort", "Messdauer (min)", "Thermometer", "Kinderwunsch",
                          "manuelle Auswertung", "Kommentar"])]
        for c in cycles {
            let m = c.meta
            lines.append(row([
                c.startDate.german, data.catalog(id: m.catalogID).name, m.measurementSite?.label ?? "",
                m.measurementDurationMinutes.map(String.init) ?? "", m.thermometer ?? "", m.wantsChild ? "ja" : "",
                m.useManualEvaluation ? "ja" : "", m.comment ?? "",
            ]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Erstellt das Export-ZIP. Mit Passwort wird die enthaltene Backup-Datei verschlüsselt
    /// (die CSV-Dateien bleiben lesbar und werden dann weggelassen).
    public static func exportZip(data: AppData, cycles: [Cycle], evaluations: [LocalDate: CycleEvaluation],
                                 appVersion: String?, password: String?) throws -> Data {
        var zip = ZipWriter()
        let encrypted = !(password ?? "").isEmpty
        let backup = try BackupCodec.encode(BackupPayload(data: data, appVersion: appVersion), password: password)
        if encrypted {
            zip.add("myNFP-Daten.nfpbackup", data: backup)
            zip.add("LIESMICH.txt", text: "Dieses Archiv enthält ein verschlüsseltes Backup. Zum Wiederherstellen in der App unter Mehr → Zyklusdaten Export/Import → Import auswählen.\n")
        } else {
            let bom = "\u{FEFF}"
            zip.add("Tagesdaten.csv", text: bom + dayCSV(data: data, cycles: cycles, evaluations: evaluations))
            let rows = Statistics.rows(cycles: cycles, evaluations: evaluations, data: data)
            zip.add("Zyklen.csv", text: bom + cycleCSV(rows: rows))
            zip.add("Zyklus-Einstellungen.csv", text: bom + cycleMetaCSV(cycles: cycles, data: data))
            zip.add("myNFP-Daten.json", data: backup)
            let settings = try BackupCodec.encoder(pretty: true).encode(data.settings)
            zip.add("Einstellungen.json", data: settings)
        }
        return zip.build()
    }
}
