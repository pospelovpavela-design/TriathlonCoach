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
    @Published var loggedWorkouts: [LoggedWorkout] = []
    @Published var profile: AthleteProfile = AthleteProfile()
    @Published var coaching: CoachingProfile = CoachingProfile()
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
    private var loggedWorkoutsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("logged_workouts.json")
    }

    init() {
        loadProfile()
        loadCoaching()
        loadWorkouts()
        loadHealthEntries()
        loadLoggedWorkouts()
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

    func saveCoaching(_ c: CoachingProfile) {
        coaching = c
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: "coaching_profile")
        }
    }

    private func loadCoaching() {
        guard let data = UserDefaults.standard.data(forKey: "coaching_profile"),
              let c = try? JSONDecoder().decode(CoachingProfile.self, from: data) else { return }
        coaching = c
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

    /// Workouts in the 7-day window ending on `date` (inclusive).
    func workouts(forLast7DaysEndingOn date: Date) -> [WorkoutPlanJSON] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -6, to: date) else { return [] }
        let fmt = dateFormatter
        let s = fmt.string(from: start)
        let e = fmt.string(from: date)
        return workouts.filter { $0.date >= s && $0.date <= e }.sorted { $0.date < $1.date }
    }

    // MARK: - Logged workouts (HKWorkout from Apple Health)

    func loggedWorkouts(forDay date: Date) -> [LoggedWorkout] {
        let key = dateFormatter.string(from: date)
        return loggedWorkouts.filter { $0.date == key }.sorted { $0.startTimeISO < $1.startTimeISO }
    }

    func loggedWorkouts(forLast7DaysEndingOn date: Date) -> [LoggedWorkout] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -6, to: date) else { return [] }
        let s = dateFormatter.string(from: start)
        let e = dateFormatter.string(from: date)
        return loggedWorkouts.filter { $0.date >= s && $0.date <= e }
            .sorted { $0.startTimeISO < $1.startTimeISO }
    }

    /// Re-fetch HKWorkouts for the last `daysBack+1` days and merge into store.
    /// Replaces entries by `startTimeISO` so re-fetch is idempotent.
    /// Awaits HealthKit authorization first to avoid race on app launch.
    @MainActor
    func refreshLoggedWorkouts(daysBack: Int = 13, healthReader: HealthKitReader) async {
        if !healthReader.isAuthorized {
            await healthReader.requestAuthorization()
        }
        let cal = Calendar.current
        let today = Date()
        var fetched: [LoggedWorkout] = []
        for i in 0...daysBack {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayWorkouts = await healthReader.loggedWorkouts(on: day)
            fetched.append(contentsOf: dayWorkouts)
        }
        // Merge: replace by startTimeISO. Keep older entries outside the refreshed window.
        guard let windowStart = cal.date(byAdding: .day, value: -daysBack, to: today) else { return }
        let windowStartKey = dateFormatter.string(from: windowStart)
        var byKey: [String: LoggedWorkout] = [:]
        for w in self.loggedWorkouts where w.date < windowStartKey {
            byKey[w.startTimeISO] = w
        }
        for w in fetched { byKey[w.startTimeISO] = w }
        self.loggedWorkouts = Array(byKey.values).sorted { $0.startTimeISO < $1.startTimeISO }
        saveLoggedWorkouts()
    }

    private func saveLoggedWorkouts() {
        guard let data = try? JSONEncoder().encode(loggedWorkouts) else { return }
        try? data.write(to: loggedWorkoutsFileURL, options: .atomic)
    }

    private func loadLoggedWorkouts() {
        guard let data = try? Data(contentsOf: loggedWorkoutsFileURL),
              let loaded = try? JSONDecoder().decode([LoggedWorkout].self, from: data) else { return }
        loggedWorkouts = loaded
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    // MARK: - Analytics

    func weekSummaryText(forWeek date: Date) -> String {
        let week = workouts(forWeek: date)
        let (mon, sun) = weekBounds(containing: date)
        let isoFmt = dateFormatter
        let monKey = isoFmt.string(from: mon)
        let sunKey = isoFmt.string(from: sun)
        let weekLogged = loggedWorkouts.filter { $0.date >= monKey && $0.date <= sunKey }

        guard !week.isEmpty || !weekLogged.isEmpty else { return "Нет тренировок за эту неделю." }

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
        let completedKeys = Set(trainable.filter { $0.completed }.map {
            "\($0.date)|\(HealthService.canonicalSport($0.sport))"
        })
        let extraLogged = weekLogged.filter {
            !completedKeys.contains("\($0.date)|\(HealthService.canonicalSport($0.sport))")
        }
        if !extraLogged.isEmpty {
            lines.append("\nИз Apple Health (без плана):")
            for lw in extraLogged {
                var detail = "\(Int(lw.durationMin.rounded())) мин"
                if let hr = lw.avgHR { detail += ", ♥ \(hr)" }
                if let d = lw.distanceString { detail += ", \(d)" }
                lines.append("⌚ \(lw.date) [\(lw.sport.uppercased())] \(ReportBuilder.sportName(lw.sport)) — \(detail)")
            }
        }

        let done = trainable.filter { $0.completed }.count + extraLogged.count
        let totalPlanned = trainable.reduce(0) { $0 + $1.duration_min }
        let totalActualPlanned = week.compactMap { $0.actual_duration_min }.reduce(0, +)
        let totalActualLogged = Int(extraLogged.reduce(0.0) { $0 + $1.durationMin }.rounded())
        let totalActual = totalActualPlanned + totalActualLogged

        lines.append("\nВыполнено: \(done) тренировок (\(trainable.filter { $0.completed }.count) по плану + \(extraLogged.count) из Apple Health)")
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
