import Foundation
import UserNotifications
import NFPCore

/// Lokale Benachrichtigungen. Werden nach jeder Datenänderung neu geplant.
enum NotificationService {
    static let prefix = "nfp."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    struct Planned: Identifiable, Hashable {
        let id: String
        let title: String
        let body: String
        let date: Date?
        let repeats: String?
    }

    @MainActor
    static func reschedule(model: AppModel, lastExternalBackup: Date?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard !model.isDemo else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let s = model.settings.notifications
        var requests: [UNNotificationRequest] = []
        let cal = Calendar.current
        let now = Date()

        func at(_ date: LocalDate, minutes: Int) -> Date {
            cal.date(from: DateComponents(year: date.year, month: date.month, day: date.day,
                                          hour: minutes / 60, minute: minutes % 60))!
        }

        func once(_ id: String, _ title: String, _ body: String, _ date: Date) {
            guard date > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            requests.append(UNNotificationRequest(identifier: prefix + id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        // Temperatur messen (täglich, optional andere Uhrzeit am Wochenende)
        if s.measureReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Temperatur messen"
            content.body = "Guten Morgen! Zeit für deine Basaltemperatur – noch vor dem Aufstehen."
            content.sound = .default
            if let weekend = s.measureReminderWeekendMinutes {
                for weekday in 1...7 { // 1 = Sonntag
                    let isWeekend = weekday == 1 || weekday == 7
                    let m = isWeekend ? weekend : s.measureReminderMinutes
                    var c = DateComponents()
                    c.weekday = weekday; c.hour = m / 60; c.minute = m % 60
                    requests.append(UNNotificationRequest(identifier: prefix + "measure.\(weekday)", content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
                }
            } else {
                var c = DateComponents()
                c.hour = s.measureReminderMinutes / 60; c.minute = s.measureReminderMinutes % 60
                requests.append(UNNotificationRequest(identifier: prefix + "measure", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
            }
        }

        // Periode in X Tagen
        if s.periodReminderEnabled {
            for (i, p) in model.predictions.prefix(3).enumerated() {
                let days = s.periodReminderDaysBefore
                let date = p.earliestStart.adding(days: -days)
                let text = days == 0 ? "Deine Periode beginnt voraussichtlich heute." :
                    "Deine Periode beginnt voraussichtlich in \(days) \(days == 1 ? "Tag" : "Tagen")."
                once("period.\(i)", "Periode bald", text, at(date, minutes: s.reminderMinutes))
            }
        }

        // Brust abtasten an Zyklustag X
        if s.breastExamEnabled {
            var starts: [LocalDate] = []
            if let c = model.currentCycle { starts.append(c.startDate) }
            starts += model.predictions.prefix(3).map(\.likelyStart)
            for (i, start) in starts.enumerated() {
                let date = start.adding(days: s.breastExamCycleDay - 1)
                once("breast.\(i)", "Brust abtasten", "Heute ist ein guter Tag für die monatliche Selbstuntersuchung der Brust.",
                     at(date, minutes: s.reminderMinutes))
            }
        }

        // Phasenwechsel im aktuellen Zyklus
        if s.phaseChangeEnabled, let c = model.currentCycle, let ev = model.evaluation(for: c) {
            if ev.startPhase.infertileUntilDay > 0 {
                let firstFertile = c.date(ofDay: ev.startPhase.infertileUntilDay + 1)
                once("phase.fertile", "Fruchtbare Phase", "Laut Auswertung beginnt heute die fruchtbare Phase.",
                     at(firstFertile, minutes: max(0, s.measureReminderMinutes - 15)))
            }
            if let d = ev.infertileFromEveningOfDay {
                once("phase.infertile", "Auswertung abgeschlossen",
                     "Laut Doppelkontrolle beginnt heute Abend die unfruchtbare Phase nach dem Eisprung. Bitte prüfe die Auswertung.",
                     at(c.date(ofDay: d), minutes: 18 * 60))
            }
        }

        // Backup-Erinnerung
        if s.backupReminderEnabled, !model.data.days.isEmpty {
            let base = lastExternalBackup ?? now
            var date = cal.date(byAdding: .day, value: 30, to: base)!
            if date <= now { date = cal.date(byAdding: .day, value: 1, to: now)! }
            let day = LocalDate(date)
            once("backup", "Datensicherung", "Sichere deine Zyklusdaten außerhalb des iPhones (Mehr → Datensicherung).",
                 at(day, minutes: s.reminderMinutes))
        }

        for r in requests.prefix(60) {
            try? await center.add(r)
        }
    }

    /// Zeitplan der geplanten Benachrichtigungen
    static func planned() async -> [Planned] {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(prefix) }.map { r in
            let trigger = r.trigger as? UNCalendarNotificationTrigger
            var repeats: String?
            if trigger?.repeats == true {
                let c = trigger!.dateComponents
                let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
                if let wd = c.weekday {
                    let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
                    repeats = "jeden \(names[(wd - 1) % 7]) um \(time)"
                } else {
                    repeats = "täglich um \(time)"
                }
            }
            return Planned(id: r.identifier, title: r.content.title, body: r.content.body,
                           date: trigger?.nextTriggerDate(), repeats: repeats)
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}
