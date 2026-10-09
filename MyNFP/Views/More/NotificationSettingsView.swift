import SwiftUI
import UserNotifications
import UIKit
import NFPCore

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(BackupService.self) private var backup
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var planned: [NotificationService.Planned] = []

    private func binding<T>(_ keyPath: WritableKeyPath<NotificationSettings, T>) -> Binding<T> {
        Binding(get: { model.settings.notifications[keyPath: keyPath] },
                set: { v in
                    model.updateSettings { $0.notifications[keyPath: keyPath] = v }
                    Task { await ensureAuthorization() }
                })
    }

    private func timeBinding(_ keyPath: WritableKeyPath<NotificationSettings, Int>) -> Binding<Date> {
        Binding(get: {
            let m = model.settings.notifications[keyPath: keyPath]
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            model.updateSettings { $0.notifications[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
        })
    }

    var body: some View {
        Form {
            if status == .denied {
                Section {
                    Label("Benachrichtigungen sind in den iOS-Einstellungen deaktiviert.", systemImage: "bell.slash")
                        .foregroundStyle(.orange)
                    Button("iOS-Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }

            Section("Temperatur messen") {
                Toggle("Tägliche Erinnerung", isOn: binding(\.measureReminderEnabled))
                if model.settings.notifications.measureReminderEnabled {
                    DatePicker("Uhrzeit", selection: timeBinding(\.measureReminderMinutes), displayedComponents: .hourAndMinute)
                    Toggle("Andere Uhrzeit am Wochenende", isOn: Binding(
                        get: { model.settings.notifications.measureReminderWeekendMinutes != nil },
                        set: { on in model.updateSettings { $0.notifications.measureReminderWeekendMinutes = on ? 8 * 60 : nil } }))
                    if model.settings.notifications.measureReminderWeekendMinutes != nil {
                        DatePicker("Wochenende", selection: Binding(get: {
                            let m = model.settings.notifications.measureReminderWeekendMinutes ?? 480
                            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
                        }, set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            model.updateSettings { $0.notifications.measureReminderWeekendMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
                        }), displayedComponents: .hourAndMinute)
                    }
                }
            }

            Section("Zyklus") {
                Toggle("Periode in … Tagen", isOn: binding(\.periodReminderEnabled))
                if model.settings.notifications.periodReminderEnabled {
                    Stepper("\(model.settings.notifications.periodReminderDaysBefore) Tage vorher",
                            value: binding(\.periodReminderDaysBefore), in: 0...10)
                }
                Toggle("Brust abtasten", isOn: binding(\.breastExamEnabled))
                if model.settings.notifications.breastExamEnabled {
                    Stepper("an Zyklustag \(model.settings.notifications.breastExamCycleDay)",
                            value: binding(\.breastExamCycleDay), in: 1...20)
                }
                Toggle("Wechsel fruchtbar / unfruchtbar", isOn: binding(\.phaseChangeEnabled))
                DatePicker("Uhrzeit für Hinweise", selection: timeBinding(\.reminderMinutes), displayedComponents: .hourAndMinute)
            }

            Section {
                Toggle("Backup-Erinnerung", isOn: binding(\.backupReminderEnabled))
            } footer: {
                Text("Erinnert dich, wenn deine Daten länger als 30 Tage nicht außerhalb des iPhones gesichert wurden.")
            }

            Section("Zeitplan") {
                if planned.isEmpty {
                    Text("Keine geplanten Benachrichtigungen.").foregroundStyle(.secondary)
                }
                ForEach(planned) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.subheadline.weight(.semibold))
                        Text(p.repeats ?? p.date?.germanDateTime ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Benachrichtigungen")
        .environment(\.locale, Locale(identifier: "de_DE"))
        .task { await refresh() }
        .onChange(of: model.settings.notifications) {
            Task {
                await NotificationService.reschedule(model: model, lastExternalBackup: backup.lastExternalBackup)
                await refresh()
            }
        }
    }

    private func ensureAuthorization() async {
        if await NotificationService.authorizationStatus() == .notDetermined {
            _ = await NotificationService.requestAuthorization()
        }
        await NotificationService.reschedule(model: model, lastExternalBackup: backup.lastExternalBackup)
        await refresh()
    }

    private func refresh() async {
        status = await NotificationService.authorizationStatus()
        planned = await NotificationService.planned()
    }
}
