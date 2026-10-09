import SwiftUI
import NFPCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
            VStack(spacing: 0) {
                if model.isDemo { DemoBanner() }
                TabView(selection: $model.selectedTab) {
                    ChartScreen()
                        .tabItem { Label("Kurve", systemImage: "chart.xyaxis.line") }
                        .tag(AppTab.chart)
                    CycleListView()
                        .tabItem { Label("Zyklen", systemImage: "list.bullet.rectangle") }
                        .tag(AppTab.cycles)
                    PeriodCalendarView()
                        .tabItem { Label("Kalender", systemImage: "calendar") }
                        .tag(AppTab.calendar)
                    StatisticsView()
                        .tabItem { Label("Statistik", systemImage: "chart.bar") }
                        .tag(AppTab.statistics)
                    MoreView()
                        .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
                        .tag(AppTab.more)
                }
            }
            .sheet(item: $model.editingDate) { date in
                DayEntryView(date: date)
            }
            .fullScreenCover(isPresented: Binding(get: { !model.settings.acceptedDisclaimer && !lock.isLocked },
                                                  set: { _ in })) {
                DisclaimerView(showsAccept: true)
            }
            .alert("Datenwiederherstellung", isPresented: Binding(get: { model.recoveryMessage != nil },
                                                                  set: { if !$0 { model.recoveryMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.recoveryMessage ?? "")
            }

            if lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if scenePhase != .active && lock.isEnabled {
                // Sichtschutz im App-Umschalter
                PrivacyCover().zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
    }
}

struct DemoBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Image(systemName: "eye")
            Text("Demo-Modus – Beispieldaten, nichts wird gespeichert")
                .font(.footnote.weight(.semibold))
            Spacer()
            Button("Beenden") { model.exitDemo() }
                .font(.footnote.bold())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(Color.orange)
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}
