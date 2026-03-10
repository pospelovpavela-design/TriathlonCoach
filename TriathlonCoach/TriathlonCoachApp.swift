import SwiftUI

@main
struct TriathlonCoachApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var wkManager = WorkoutKitManager()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $store.selectedTab) {
                ChatView()
                    .tabItem { Label("Тренер", systemImage: "sparkles.circle.fill") }
                    .tag(0)

                WeekCalendarView()
                    .tabItem { Label("Неделя", systemImage: "calendar") }
                    .tag(1)

                AnalyticsView()
                    .tabItem { Label("Итоги", systemImage: "chart.bar.fill") }
                    .tag(2)

                SettingsView()
                    .tabItem { Label("Настройки", systemImage: "gear") }
                    .tag(3)
            }
            .environmentObject(store)
            .environmentObject(wkManager)
            .tint(.blue)
            .preferredColorScheme(.dark)
            .task {
                await wkManager.requestAuthorization()
                await wkManager.loadSavedPlans()
            }
        }
    }
}
