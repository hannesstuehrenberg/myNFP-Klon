import SwiftUI
import NFPCore

/// Zeichnet das Zyklusblatt (ohne Beschriftungsspalte).
struct CycleChartCanvas: View {
    let ctx: ChartContext
    let layout: ChartLayout

    var body: some View {
        Canvas { g, size in
            ChartPainter(ctx: ctx, layout: layout).draw(in: &g, size: size)
        }
        .frame(width: layout.contentWidth, height: layout.totalHeight)
    }
}

/// Beschriftungsspalte links (Zeilennamen und Temperaturskala).
struct ChartLabelsCanvas: View {
    let layout: ChartLayout

    var body: some View {
        Canvas { g, size in
            for row in layout.rows {
                switch row.kind {
                case .temperature:
                    var t = layout.tempRange.upperBound
                    while t >= layout.tempRange.lowerBound - 0.001 {
                        let y = layout.y(temp: t)
                        let isMajor = abs((t * 2).rounded() - t * 2) < 0.001
                        let text = Text(TemperatureInput.format(t).dropLast(1))
                            .font(.system(size: isMajor ? 10 : 9, weight: isMajor ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(isMajor ? Color.primary : Color.secondary)
                        g.draw(text, at: CGPoint(x: size.width - 6, y: y), anchor: .trailing)
                        t -= 0.1
                        t = (t * 100).rounded() / 100
                    }
                case .bars:
                    continue
                default:
                    let text = Text(row.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondary)
                    g.draw(text, at: CGPoint(x: 6, y: row.y + row.height / 2), anchor: .leading)
                }
                // Trennlinie
                if row.kind != .bars && row.kind != .date {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: row.y))
                    p.addLine(to: CGPoint(x: size.width, y: row.y))
                    g.stroke(p, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                }
            }
        }
        .frame(width: layout.labelW, height: layout.totalHeight)
    }
}

struct ChartPainter {
    let ctx: ChartContext
    let layout: ChartLayout

    private var cw: CGFloat { layout.colW }
    private var lastObservedDay: Int {
        ctx.cycle.isCompleted ? ctx.cycle.length : min(ctx.cycle.length, ctx.cycle.cycleDay(of: ctx.today))
    }

    func draw(in g: inout GraphicsContext, size: CGSize) {
        drawColumns(&g, size: size)
        drawRowSeparators(&g, size: size)
        for row in layout.rows {
            switch row.kind {
            case .date: drawDates(&g, row)
            case .time: drawTimes(&g, row)
            case .bars: drawBars(&g, row)
            case .temperature: drawTemperature(&g, row)
            case .cycleDay: drawCycleDays(&g, row)
            case .status: drawStatus(&g, row)
            case .bleeding: drawBleeding(&g, row)
            case .mucus: drawMucus(&g, row)
            case .peak: drawPeak(&g, row)
            case .cervix: drawCervix(&g, row)
            case .breast: drawSimple(&g, row) { $0.breast?.symbol }
            case .mittelschmerz: drawSimple(&g, row) { $0.mittelschmerz?.symbol }
            case .intercourse: drawIntercourse(&g, row)
            case .disturbances: drawIcon(&g, row, symbol: "bolt.fill", color: .orange) { !$0.disturbances.isEmpty }
            case .note: drawIcon(&g, row, symbol: "note.text", color: .secondary) { !($0.note ?? "").isEmpty }
            case .medication: drawIcon(&g, row, symbol: "pills.fill", color: .teal) { !($0.medication ?? "").isEmpty }
            case .extra(let id): drawExtra(&g, row, barID: id)
            }
        }
        drawSelection(&g, size: size)
    }

    // MARK: Raster & Spalten

    private func drawColumns(_ g: inout GraphicsContext, size: CGSize) {
        guard let temp = layout.row(.temperature) else { return }
        // Auswertungsfarben im Temperaturbereich
        if let ev = ctx.evaluation {
            for d in 1...layout.dayCount where d <= ev.dayStatuses.count {
                let s = ev.status(day: d)
                guard s != .unknown else { continue }
                let rect = CGRect(x: layout.xLeft(d), y: temp.y, width: cw, height: temp.height)
                let color = Theme.statusColor(s, wantsChild: ctx.wantsChild)
                if s == .infertileFromEvening {
                    // Halbe Spalte: ab abends unfruchtbar
                    g.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: cw / 2, height: rect.height)),
                           with: .color(color.opacity(0.08)))
                    g.fill(Path(CGRect(x: rect.midX, y: rect.minY, width: cw / 2, height: rect.height)),
                           with: .color(Theme.statusColor(.infertileAfterOvulation, wantsChild: ctx.wantsChild).opacity(0.12)))
                } else {
                    g.fill(Path(rect), with: .color(color.opacity(s.isInfertile ? 0.12 : 0.06)))
                }
            }
        }
        // Heute
        if ctx.cycle.contains(ctx.today) || ctx.cycle.cycleDay(of: ctx.today) <= layout.dayCount {
            let td = ctx.cycle.cycleDay(of: ctx.today)
            if td >= 1 && td <= layout.dayCount {
                g.fill(Path(CGRect(x: layout.xLeft(td), y: 0, width: cw, height: size.height)),
                       with: .color(Theme.accent.opacity(0.07)))
            }
        }
        // Zukunft abdunkeln
        if !ctx.cycle.isCompleted {
            let first = lastObservedDay + 1
            if first <= layout.dayCount {
                g.fill(Path(CGRect(x: layout.xLeft(first), y: temp.y, width: CGFloat(layout.dayCount - first + 1) * cw,
                                   height: temp.height)), with: .color(.gray.opacity(0.05)))
            }
        }
        // Vertikale Linien
        for d in 0...layout.dayCount {
            var p = Path()
            let x = CGFloat(d) * cw
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            let isWeekStart = d < layout.dayCount && ctx.date(ofDay: d + 1).isoWeekday == 1
            g.stroke(p, with: .color(.secondary.opacity(isWeekStart ? 0.3 : 0.15)), lineWidth: isWeekStart ? 0.8 : 0.5)
        }
        // Horizontale Temperaturlinien (0,05 / 0,1 / 0,5)
        var t = layout.tempRange.lowerBound
        while t <= layout.tempRange.upperBound + 0.001 {
            let y = layout.y(temp: t)
            let tenth = abs((t * 10).rounded() - t * 10) < 0.01
            let half = abs((t * 2).rounded() - t * 2) < 0.01
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: layout.contentWidth, y: y))
            let opacity = half ? 0.35 : (tenth ? 0.2 : 0.07)
            g.stroke(p, with: .color(.secondary.opacity(opacity)), lineWidth: half ? 0.8 : 0.5)
            t += 0.05
        }
    }

    private func drawRowSeparators(_ g: inout GraphicsContext, size: CGSize) {
        for row in layout.rows where row.kind != .bars && row.kind != .date {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: row.y))
            p.addLine(to: CGPoint(x: size.width, y: row.y))
            g.stroke(p, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
        }
    }

    private func drawSelection(_ g: inout GraphicsContext, size: CGSize) {
        guard let d = ctx.selectedDay, d >= 1, d <= layout.dayCount else { return }
        let rect = CGRect(x: layout.xLeft(d) + 1, y: 1, width: cw - 2, height: size.height - 2)
        g.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.accent), lineWidth: 2)
    }

    // MARK: Datum, Uhrzeit, Zyklustag

    private func drawDates(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...layout.dayCount {
            let date = ctx.date(ofDay: d)
            let color: Color = date.isWeekend ? .red : .primary
            let x = layout.xCenter(d)
            let isToday = date == ctx.today
            if isToday {
                let r = CGRect(x: layout.xLeft(d) + 2, y: row.y + 2, width: cw - 4, height: row.height - 4)
                g.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Theme.accent.opacity(0.25)))
            }
            g.draw(Text(date.weekdayShortGerman).font(.system(size: 8 * min(ctx.zoom, 1.2))).foregroundStyle(color.opacity(0.8)),
                   at: CGPoint(x: x, y: row.y + row.height * 0.22))
            g.draw(Text(String(format: "%02d", date.day)).font(.system(size: 11 * min(ctx.zoom, 1.2), weight: isToday ? .bold : .semibold).monospacedDigit())
                    .foregroundStyle(color),
                   at: CGPoint(x: x, y: row.y + row.height * 0.52))
            if d == 1 || date.day == 1 {
                let month = String(LocalDate.germanMonthNames[date.month - 1].prefix(3))
                g.draw(Text(month).font(.system(size: 7.5 * min(ctx.zoom, 1.2), weight: .medium)).foregroundStyle(Color.secondary),
                       at: CGPoint(x: x, y: row.y + row.height * 0.83))
            } else {
                g.draw(Text(String(format: "%02d", date.month)).font(.system(size: 7.5 * min(ctx.zoom, 1.2)).monospacedDigit()).foregroundStyle(Color.secondary),
                       at: CGPoint(x: x, y: row.y + row.height * 0.83))
            }
        }
    }

    private func drawTimes(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...layout.dayCount {
            guard let m = ctx.entry(d)?.measurementTime else { continue }
            let text = "\(m / 60):\(String(format: "%02d", m % 60))"
            g.draw(Text(text).font(.system(size: 7.5 * min(ctx.zoom, 1.3)).monospacedDigit()).foregroundStyle(Color.secondary),
                   at: CGPoint(x: layout.xCenter(d), y: row.y + row.height / 2))
        }
    }

    private func drawCycleDays(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...layout.dayCount {
            let isFHM = ctx.evaluation?.temperature.firstHigherDay == d
            g.draw(Text("\(d)").font(.system(size: 9.5 * min(ctx.zoom, 1.2), weight: isFHM ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isFHM ? Theme.higherValues : Color.primary),
                   at: CGPoint(x: layout.xCenter(d), y: row.y + row.height / 2))
        }
    }

    // MARK: Balken (Prognose, Schwangerschaft)

    private func drawBars(_ g: inout GraphicsContext, _ row: ChartRow) {
        guard let ev = ctx.evaluation else { return }
        let h = row.height * 0.6
        let y = row.y + (row.height - h) / 2
        if let p = ev.pregnancy, !ctx.settings.hidePregnancyBar, let fhm = ev.temperature.firstHigherDay {
            let startDay = fhm + CycleEvaluator.pregnancyHighPhaseDay - 1
            if startDay <= layout.dayCount {
                let rect = CGRect(x: layout.xLeft(startDay), y: y, width: CGFloat(layout.dayCount - startDay + 1) * cw, height: h)
                g.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(Theme.pregnancy.opacity(0.85)))
            }
            _ = p
        } else if let f = ev.periodForecast {
            let a = ctx.cycle.cycleDay(of: f.earliest)
            let b = ctx.cycle.cycleDay(of: f.latest)
            guard a <= layout.dayCount else { return }
            let rect = CGRect(x: layout.xLeft(max(1, a)), y: y, width: CGFloat(min(b, layout.dayCount) - max(1, a) + 1) * cw, height: h)
            g.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(Theme.forecast.opacity(0.75)))
        }
    }

    // MARK: Temperatur

    private func drawTemperature(_ g: inout GraphicsContext, _ row: ChartRow) {
        let ev = ctx.evaluation
        let highlight = ctx.settings.highlightRelevantTemperatures
        let temp = ev?.temperature

        // Hilfslinie
        if let cl = temp?.coverline {
            let fromDay = temp?.lowDays.first ?? max(1, (temp?.firstHigherDay ?? 1) - 6)
            let toDay = max(temp?.completionDay ?? temp?.higherDays.last ?? temp?.firstHigherDay ?? fromDay, fromDay) + 1
            var p = Path()
            let y = layout.y(temp: cl)
            p.move(to: CGPoint(x: layout.xLeft(fromDay), y: y))
            p.addLine(to: CGPoint(x: min(layout.contentWidth, layout.xLeft(toDay) + cw), y: y))
            g.stroke(p, with: .color(Theme.coverline), style: StrokeStyle(lineWidth: 1.5))
        }

        // Kurve
        var points: [(day: Int, point: CGPoint)] = []
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            if let t = ctx.entry(d)?.validTemperature {
                points.append((d, CGPoint(x: layout.xCenter(d), y: layout.y(temp: t))))
            }
        }
        for i in 1..<max(1, points.count) {
            let a = points[i - 1], b = points[i]
            var p = Path()
            p.move(to: a.point)
            p.addLine(to: b.point)
            let gap = b.day - a.day > 1
            g.stroke(p, with: .color(Theme.curve.opacity(0.8)),
                     style: StrokeStyle(lineWidth: 1.3, dash: gap ? [3, 3] : []))
        }

        let r: CGFloat = 3.2 * min(ctx.zoom, 1.3)
        let lowSet = Set(temp?.lowDays ?? [])
        let higher = temp?.higherDays ?? []
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let e = ctx.entry(d), let t = e.temperature else { continue }
            let c = CGPoint(x: layout.xCenter(d), y: layout.y(temp: t))
            let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            if e.excluded {
                g.stroke(dot, with: .color(Theme.excluded), lineWidth: 1.2)
                g.draw(Text("( )").font(.system(size: 8)).foregroundStyle(Theme.excluded), at: CGPoint(x: c.x, y: c.y - 2.6 * r))
                continue
            }
            g.fill(dot, with: .color(Theme.curve))
            guard highlight else { continue }
            if lowSet.contains(d) {
                let ring = Path(ellipseIn: CGRect(x: c.x - r - 2.5, y: c.y - r - 2.5, width: 2 * r + 5, height: 2 * r + 5))
                g.stroke(ring, with: .color(Theme.lowValues), lineWidth: 1.3)
            }
            if let idx = higher.firstIndex(of: d) {
                let ring = Path(ellipseIn: CGRect(x: c.x - r - 2.5, y: c.y - r - 2.5, width: 2 * r + 5, height: 2 * r + 5))
                g.stroke(ring, with: .color(Theme.higherValues), lineWidth: 1.5)
                g.draw(Text("\(idx + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.higherValues),
                       at: CGPoint(x: c.x, y: c.y - 3.4 * r))
            }
            if temp?.ignoredDropDay == d {
                g.draw(Text("·").font(.system(size: 14, weight: .black)).foregroundStyle(Theme.coverline),
                       at: CGPoint(x: c.x, y: c.y + 2.8 * r))
            }
        }
        // Ausgeklammerte Werte: Hinweis auf Störungen ohne Temperatur
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let e = ctx.entry(d), e.temperature == nil, e.disturbances.contains(.illness) else { continue }
            g.draw(Text("krank").font(.system(size: 7)).foregroundStyle(Theme.excluded),
                   at: CGPoint(x: layout.xCenter(d), y: row.y + row.height - 8))
        }
    }

    // MARK: Status

    private func drawStatus(_ g: inout GraphicsContext, _ row: ChartRow) {
        guard let ev = ctx.evaluation else { return }
        let h = row.height * 0.55
        let y = row.y + (row.height - h) / 2
        for d in 1...min(layout.dayCount, ev.dayStatuses.count) {
            let s = ev.status(day: d)
            guard s != .unknown else { continue }
            let x = layout.xLeft(d)
            if s == .infertileFromEvening {
                g.fill(Path(CGRect(x: x, y: y, width: cw / 2, height: h)), with: .color(Theme.statusColor(.fertile, wantsChild: ctx.wantsChild)))
                g.fill(Path(CGRect(x: x + cw / 2, y: y, width: cw / 2, height: h)),
                       with: .color(Theme.statusColor(.infertileAfterOvulation, wantsChild: ctx.wantsChild)))
            } else {
                g.fill(Path(CGRect(x: x, y: y, width: cw, height: h)), with: .color(Theme.statusColor(s, wantsChild: ctx.wantsChild)))
            }
        }
    }

    // MARK: Symptome

    private func center(_ row: ChartRow, _ d: Int) -> CGPoint {
        CGPoint(x: layout.xCenter(d), y: row.y + row.height / 2)
    }

    private var symbolFont: Font { .system(size: 10 * min(ctx.zoom, 1.25), weight: .semibold) }

    private func drawBleeding(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let e = ctx.entry(d), let b = e.bleeding else { continue }
            let c = center(row, d)
            let sizes: [CGFloat] = [0, 3, 5, 6.5, 8]
            let size: CGFloat = sizes[b.rawValue] * min(ctx.zoom, 1.3)
            let rect = CGRect(x: c.x - size, y: c.y - size, width: 2 * size, height: 2 * size)
            if b == .spotting {
                g.fill(Path(ellipseIn: rect), with: .color(Theme.bleeding.opacity(0.6)))
            } else {
                g.fill(Path(ellipseIn: rect), with: .color(Theme.bleeding))
            }
            if e.isFirstCycleDay {
                g.draw(Text("1").font(.system(size: 8, weight: .bold)).foregroundStyle(.white), at: c)
            }
        }
    }

    private func drawMucus(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let m = ctx.entry(d)?.mucus, let s = m.symbol else { continue }
            let text = ctx.settings.effectiveSubdifferentiation ? (m.displaySymbol ?? s.label) : s.label
            let color: Color = {
                switch s {
                case .sPlus: return Theme.peak
                case .s: return Theme.fertile
                case .f: return .orange
                default: return .secondary
                }
            }()
            g.draw(Text(text).font(symbolFont).foregroundStyle(color), at: center(row, d))
        }
    }

    private func drawPeak(_ g: inout GraphicsContext, _ row: ChartRow) {
        guard let ev = ctx.evaluation else { return }
        let primary = ev.doubleCheck == .mucus ? ev.mucus : ev.cervix
        guard let peak = primary.peakDay, primary.status != .none else { return }
        if peak <= layout.dayCount {
            let c = center(row, peak)
            let rect = CGRect(x: c.x - cw * 0.42, y: c.y - row.height * 0.38, width: cw * 0.84, height: row.height * 0.76)
            g.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.peak.opacity(primary.status == .completed ? 0.9 : 0.4)))
            g.draw(Text("HP").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white), at: c)
        }
        for (i, d) in primary.afterPeakDays.enumerated() where d <= layout.dayCount {
            g.draw(Text("\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.peak), at: center(row, d))
        }
    }

    private func drawCervix(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let c = ctx.entry(d)?.cervix, let s = c.displaySymbol else { continue }
            var p = center(row, d)
            // Position: tief = unten, hoch = oben
            if let pos = c.position { p.y += CGFloat(1 - pos.rawValue) * row.height * 0.18 }
            g.draw(Text(s).font(.system(size: 9 * min(ctx.zoom, 1.25), weight: .semibold))
                    .foregroundStyle(c.isClosedAndHard ? Color.secondary : Theme.fertile), at: p)
        }
    }

    private func drawSimple(_ g: inout GraphicsContext, _ row: ChartRow, _ value: (DayEntry) -> String?) {
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let e = ctx.entry(d), let v = value(e) else { continue }
            g.draw(Text(v).font(.system(size: 9 * min(ctx.zoom, 1.25), weight: .semibold)).foregroundStyle(Color.primary),
                   at: center(row, d))
        }
    }

    private func drawIntercourse(_ g: inout GraphicsContext, _ row: ChartRow) {
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let i = ctx.entry(d)?.intercourse else { continue }
            let img = Text(Image(systemName: i == .unprotected ? "heart.fill" : "heart.circle"))
                .font(.system(size: 11 * min(ctx.zoom, 1.25)))
                .foregroundStyle(i == .unprotected ? Theme.fertile : Color.secondary)
            g.draw(img, at: center(row, d))
        }
    }

    private func drawIcon(_ g: inout GraphicsContext, _ row: ChartRow, symbol: String, color: Color, _ has: (DayEntry) -> Bool) {
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let e = ctx.entry(d), has(e) else { continue }
            g.draw(Text(Image(systemName: symbol)).font(.system(size: 10 * min(ctx.zoom, 1.25))).foregroundStyle(color),
                   at: center(row, d))
        }
    }

    private func drawExtra(_ g: inout GraphicsContext, _ row: ChartRow, barID: String) {
        guard let bar = ctx.settings.bars.first(where: { $0.id == barID }) else { return }
        for d in 1...min(layout.dayCount, ctx.cycle.length) {
            guard let v = ctx.entry(d)?.bars[barID], !v.isEmpty else { continue }
            let c = center(row, d)
            switch bar.kind {
            case .sliderRedGreen, .sliderGreenRed:
                guard let n = v.number else { continue }
                let r = row.height * 0.32
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Theme.sliderColor(n, redToGreen: bar.kind == .sliderRedGreen)))
                g.draw(Text("\(n)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white), at: c)
            case .goalReached:
                drawFlag(&g, c, v.flag, symbol: "flag.checkered")
            case .done:
                drawFlag(&g, c, v.flag, symbol: "checkmark.seal.fill")
            case .takenIcon:
                drawFlag(&g, c, v.flag, symbol: "checkmark.circle.fill")
            case .takenYes:
                g.draw(Text(v.flag == true ? "ja" : "nein").font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(v.flag == true ? Color.green : Color.secondary), at: c)
            case .intensity:
                let level = (v.selections.first.flatMap { BarKind.intensityLevels.firstIndex(of: $0) } ?? 0) + 1
                let maxH = row.height * 0.75
                let h = maxH * CGFloat(level) / 5
                let rect = CGRect(x: c.x - cw * 0.22, y: c.y + maxH / 2 - h, width: cw * 0.44, height: h)
                g.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Theme.sliderColor(level, redToGreen: false)))
            case .textIcon:
                g.draw(Text(Image(systemName: bar.icon ?? "text.bubble")).font(.system(size: 10)).foregroundStyle(Color.secondary), at: c)
            case .textValue:
                let t = v.text ?? ""
                let n = (t.contains(".") || t.contains(",")) ? 3 : 2
                g.draw(Text(String(t.prefix(n))).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.primary), at: c)
            case .singleChoice:
                g.draw(Text(shortLabel(v.selections.first ?? "")).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(choiceColor(v.selections.first ?? "")), at: c)
            case .multiChoice:
                let text = v.selections.count == 1 ? shortLabel(v.selections[0]) : "\(v.selections.count)"
                g.draw(Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.primary), at: c)
            }
        }
    }

    private func drawFlag(_ g: inout GraphicsContext, _ c: CGPoint, _ flag: Bool?, symbol: String) {
        let yes = flag ?? false
        g.draw(Text(Image(systemName: yes ? symbol : "xmark")).font(.system(size: yes ? 11 : 8))
                .foregroundStyle(yes ? Color.green : Color.secondary), at: c)
    }

    private func shortLabel(_ s: String) -> String {
        switch s {
        case "positiv": return "+"
        case "negativ": return "−"
        case "schwach positiv": return "(+)"
        case "unklar": return "?"
        default: return String(s.prefix(2))
        }
    }

    private func choiceColor(_ s: String) -> Color {
        switch s {
        case "positiv": return Theme.fertile
        case "schwach positiv": return .orange
        default: return .primary
        }
    }
}
