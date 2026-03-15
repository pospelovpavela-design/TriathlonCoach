import Foundation
import SwiftUI
import Combine

// MARK: - Athlete Profile

struct AthleteProfile: Codable {
    var name: String = "Павел"
    var maxHR: Int = 185
    var restingHR: Int = 55
    var weeklyHoursGoal: Double = 8.0
    var notes: String = ""

    var claudeContext: String {
        var parts = ["Атлет: \(name)"]
        parts.append("Макс. пульс: \(maxHR) уд/мин, пульс покоя: \(restingHR) уд/мин")
        parts.append("Целевой объём: \(weeklyHoursGoal) ч/нед")
        if !notes.isEmpty { parts.append("О себе: \(notes)") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - App Store

@MainActor
class AppStore: ObservableObject {

    @Published var workouts: [WorkoutPlanJSON] = []
    @Published var healthEntries: [HealthDayEntry] = []
    @Published var profile: AthleteProfile = AthleteProfile()
    @Published var pendingPrompt: String = ""
    @Published var selectedTab: Int = 0

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("workouts_store.json")
    }
    private var healthFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("health_entries.json")
    }

    init() {
        loadProfile()
        loadWorkouts()
        loadHealthEntries()
    }

    // MARK: - Persistence

    private func loadWorkouts() {
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([WorkoutPlanJSON].self, from: data),
           !loaded.isEmpty {
            workouts = loaded.sorted { $0.date < $1.date }
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacy = docs.appendingPathComponent("workouts_updated.json")
        if let data = try? Data(contentsOf: legacy),
           let loaded = try? JSONDecoder().decode([WorkoutPlanJSON].self, from: data),
           !loaded.isEmpty {
            workouts = loaded.sorted { $0.date < $1.date }
            save()
            return
        }
        workouts = WorkoutLoader.demoWorkouts()
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(workouts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func saveProfile(_ p: AthleteProfile) {
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: "athlete_profile")
        }
    }

    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: "athlete_profile"),
              let p = try? JSONDecoder().decode(AthleteProfile.self, from: data) else { return }
        profile = p
    }

    // MARK: - Mutations

    func addOrReplace(_ newWorkouts: [WorkoutPlanJSON]) {
        for w in newWorkouts {
            if let idx = workouts.firstIndex(where: { $0.stableKey == w.stableKey }) {
                workouts[idx] = w
            } else {
                workouts.append(w)
            }
        }
        workouts.sort { $0.date < $1.date }
        save()
    }

    func update(_ workout: WorkoutPlanJSON) {
        guard let idx = workouts.firstIndex(where: { $0.stableKey == workout.stableKey }) else { return }
        workouts[idx] = workout
        save()
    }

    func delete(_ workout: WorkoutPlanJSON) {
        workouts.removeAll { $0.stableKey == workout.stableKey }
        save()
    }

    // MARK: - Health Entries

    func healthEntryOrNil(for date: String) -> HealthDayEntry? {
        healthEntries.first { $0.date == date }
    }

    func updateHealthEntry(_ entry: HealthDayEntry) {
        if let idx = healthEntries.firstIndex(where: { $0.date == entry.date }) {
            healthEntries[idx] = entry
        } else {
            healthEntries.append(entry)
        }
        healthEntries.sort { $0.date > $1.date }
        saveHealthEntries()
    }

    private func saveHealthEntries() {
        guard let data = try? JSONEncoder().encode(healthEntries) else { return }
        try? data.write(to: healthFileURL, options: .atomic)
    }

    private func loadHealthEntries() {
        guard let data = try? Data(contentsOf: healthFileURL),
              let loaded = try? JSONDecoder().decode([HealthDayEntry].self, from: data) else { return }
        healthEntries = loaded
    }

    func loadFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([WorkoutPlanJSON].self, from: data) else { return }
        addOrReplace(loaded)
    }

    // MARK: - Week queries

    func weekBounds(containing date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let daysToMon = weekday == 1 ? -6 : -(weekday - 2)
        let monday = cal.date(byAdding: .day, value: daysToMon, to: date) ?? date
        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? date
        return (monday, sunday)
    }

    func workouts(forWeek date: Date) -> [WorkoutPlanJSON] {
        let (mon, sun) = weekBounds(containing: date)
        let fmt = dateFormatter
        let start = fmt.string(from: mon)
        let end = fmt.string(from: sun)
        return workouts.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }

    func workouts(forDay date: Date) -> [WorkoutPlanJSON] {
        let key = dateFormatter.string(from: date)
        return workouts.filter { $0.date == key }
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    // MARK: - Analytics

    func weekSummaryText(forWeek date: Date) -> String {
        let week = workouts(forWeek: date)
        guard !week.isEmpty else { return "Нет тренировок за эту неделю." }

        let (mon, _) = weekBounds(containing: date)
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "ru_RU")

        var lines = ["📊 Итоги недели (нед. от \(fmt.string(from: mon))):\n"]
        for w in week {
            let status = w.completed ? "✅" : "⬜"
            var detail = "\(w.duration_min) мин план."
            if let actual = w.actual_duration_min { detail += " / \(actual) мин факт." }
            if let hr = w.actual_avg_hr { detail += ", ср. пульс \(hr)" }
            lines.append("\(status) \(w.date) [\(w.sport.uppercased())] \(w.title) — \(detail)")
            if !w.notes_after.isEmpty { lines.append("   Заметки: \(w.notes_after)") }
        }

        let trainable = week.filter { $0.sport != "rest" }
        let done = trainable.filter { $0.completed }.count
        let totalPlanned = trainable.reduce(0) { $0 + $1.duration_min }
        let totalActual = week.compactMap { $0.actual_duration_min }.reduce(0, +)

        lines.append("\nВыполнено: \(done)/\(trainable.count) тренировок")
        lines.append("Объём: план \(totalPlanned) мин, факт \(totalActual) мин")
        lines.append("\n\(profile.claudeContext)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Next week date range helper

    func nextWeekRange() -> String {
        let cal = Calendar.current
        let (mon, _) = weekBounds(containing: Date())
        guard let nextMon = cal.date(byAdding: .weekOfYear, value: 1, to: mon),
              let nextSun = cal.date(byAdding: .day, value: 6, to: nextMon) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(fmt.string(from: nextMon)) – \(fmt.string(from: nextSun))"
    }

    func currentWeekRange() -> String {
        let (mon, sun) = weekBounds(containing: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(fmt.string(from: mon)) – \(fmt.string(from: sun))"
    }

    func nextWeekRange(relativeTo date: Date) -> String {
        let cal = Calendar.current
        let (mon, _) = weekBounds(containing: date)
        guard let nextMon = cal.date(byAdding: .weekOfYear, value: 1, to: mon),
              let nextSun = cal.date(byAdding: .day, value: 6, to: nextMon) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(fmt.string(from: nextMon)) – \(fmt.string(from: nextSun))"
    }
}
