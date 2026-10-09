import SwiftUI
import NFPCore

@main
struct MyNFPApp: App {
    @State private var model = AppModel()
    @State private var lock = AppLock()
    @State private var backup = BackupService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .environment(backup)
                .preferredColorScheme(colorScheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .onAppear(perform: wire)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.didEnterBackground()
                model.didEnterBackground()
                if !model.isDemo { model.store.snapshotIfNeeded(model.data) }
            case .active:
                lock.willEnterForeground()
                model.refreshIfDayChanged()
                if !model.isDemo { backup.dailyBackupIfNeeded(data: model.data) }
                Task { await NotificationService.reschedule(model: model, lastExternalBackup: backup.lastExternalBackup) }
            default:
                break
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func wire() {
        model.onDataChanged = { [model, backup] in
            backup.scheduleAutoBackup { model.data }
            Task { await NotificationService.reschedule(model: model, lastExternalBackup: backup.lastExternalBackup) }
        }
    }
}
