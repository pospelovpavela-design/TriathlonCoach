import Foundation

class WorkoutLoader: ObservableObject {

    @Published var workouts: [WorkoutPlanJSON] = []
    @Published var loadError: String?

    // MARK: - Загрузка из файла (Documents или Bundle)

    func loadFromDocuments() {
        let urls = [
            // Сначала смотрим в Documents (файлы переданные через AirDrop/Files)
            documentsURL(filename: "pre_shift_week.json"),
            documentsURL(filename: "shift_week1.json"),
        ].compactMap { $0 }

        var all: [WorkoutPlanJSON] = []

        for url in urls {
            if let loaded = load(from: url) {
                all.append(contentsOf: loaded)
            }
        }

        if all.isEmpty {
            // Fallback — встроенные демо-данные
            workouts = Self.demoWorkouts()
        } else {
            workouts = all.sorted { $0.date < $1.date }
        }
    }

    func loadFromURL(_ url: URL) {
        guard let loaded = load(from: url) else { return }
        // Merge с существующими, избегая дублей по дате+названию
        let existing = Set(workouts.map { $0.title + $0.date })
        let new = loaded.filter { !existing.contains($0.title + $0.date) }
        workouts.append(contentsOf: new)
        workouts.sort { $0.date < $1.date }
    }

    private func load(from url: URL) -> [WorkoutPlanJSON]? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var workouts = try decoder.decode([WorkoutPlanJSON].self, from: data)
            return workouts
        } catch {
            loadError = "Ошибка загрузки \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func documentsURL(filename: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let url = docs?.appendingPathComponent(filename)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Сохранить обновлённый JSON (с actual_avg_hr после тренировки)

    func saveUpdated(_ workout: WorkoutPlanJSON) {
        var updated = workouts
        if let idx = updated.firstIndex(where: { $0.title == workout.title && $0.date == workout.date }) {
            updated[idx] = workout
        }
        workouts = updated

        // Сохраняем в Documents
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("workouts_updated.json")
        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: url)
        }
    }

    // MARK: - Demo данные (встроены в приложение)

    static func demoWorkouts() -> [WorkoutPlanJSON] {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let tomorrow = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)).prefix(10)
        let dayAfter = ISO8601DateFormatter().string(from: Date().addingTimeInterval(172800)).prefix(10)

        return [
            WorkoutPlanJSON(
                title: "🏃 Лёгкий бег Z1",
                sport: "run",
                date: String(today),
                duration_min: 40,
                target_zone: "Z1",
                description: "Лёгкий восстановительный бег перед вахтой",
                intervals: [
                    IntervalJSON(duration_min: 5,  zone: "Z1", note: "Разминка — шаг/трусца"),
                    IntervalJSON(duration_min: 30, zone: "Z1", note: "Лёгкий бег Z1 < 119"),
                    IntervalJSON(duration_min: 5,  zone: "Z1", note: "Заминка — шаг"),
                ],
                tags: ["run", "z1", "pre-shift"],
                rpe_target: 4,
                planned: true,
                completed: false,
                actual_avg_hr: nil,
                actual_duration_min: nil,
                notes_after: ""
            ),
            WorkoutPlanJSON(
                title: "🚴 Вело Z1–Z2",
                sport: "bike",
                date: String(tomorrow),
                duration_min: 70,
                target_zone: "Z2",
                description: "Аэробная велотренировка — последняя перед вахтой",
                intervals: [
                    IntervalJSON(duration_min: 10, zone: "Z1", note: "Разминка Z1"),
                    IntervalJSON(duration_min: 50, zone: "Z2", note: "Аэробная база 120–130"),
                    IntervalJSON(duration_min: 10, zone: "Z1", note: "Заминка Z1"),
                ],
                tags: ["bike", "z2", "pre-shift"],
                rpe_target: 5,
                planned: true,
                completed: false,
                actual_avg_hr: nil,
                actual_duration_min: nil,
                notes_after: ""
            ),
            WorkoutPlanJSON(
                title: "🏃 Лёгкий бег Z1 (короткий)",
                sport: "run",
                date: String(dayAfter),
                duration_min: 35,
                target_zone: "Z1",
                description: "Короткий лёгкий бег перед отъездом",
                intervals: [
                    IntervalJSON(duration_min: 5,  zone: "Z1", note: "Разминка"),
                    IntervalJSON(duration_min: 25, zone: "Z1", note: "Лёгкий бег Z1"),
                    IntervalJSON(duration_min: 5,  zone: "Z1", note: "Заминка + растяжка"),
                ],
                tags: ["run", "z1", "pre-shift"],
                rpe_target: 3,
                planned: true,
                completed: false,
                actual_avg_hr: nil,
                actual_duration_min: nil,
                notes_after: ""
            ),
        ]
    }
}
