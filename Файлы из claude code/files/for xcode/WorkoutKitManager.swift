import Foundation
import WorkoutKit
import HealthKit

// MARK: - WorkoutKit Manager
// Требует iOS 17+ / watchOS 10+

@MainActor
class WorkoutKitManager: ObservableObject {

    @Published var authorizationStatus: AuthStatus = .unknown
    @Published var savedWorkouts: [String] = []   // titles уже сохранённых
    @Published var isLoading = false
    @Published var lastError: String?

    enum AuthStatus {
        case unknown, authorized, denied
        var description: String {
            switch self {
            case .unknown:    return "Не определён"
            case .authorized: return "Разрешено"
            case .denied:     return "Запрещено"
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        // WorkoutKit использует HealthKit под капотом
        let store = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .denied
            lastError = "HealthKit недоступен на этом устройстве"
            return
        }

        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]

        do {
            try await store.requestAuthorization(toShare: types, read: types)
            authorizationStatus = .authorized
        } catch {
            authorizationStatus = .denied
            lastError = "Ошибка авторизации: \(error.localizedDescription)"
        }
    }

    // MARK: - Save workout plan to Watch

    func saveWorkout(_ workout: WorkoutPlanJSON) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // Пропускаем отдых/мобильность — нет смысла создавать план тренировки
        guard workout.sport != "rest", workout.sport != "mobility" else {
            lastError = "Тренировки типа 'отдых' не добавляются на часы"
            return false
        }

        do {
            // Строим отрезки (WorkoutStep)
            var steps: [WorkoutComposition] = []

            for interval in workout.intervals {
                guard let zone = HRZone.zone(for: interval.zone) else { continue }

                // Цель отрезка — время
                let goal = WorkoutGoal.time(
                    TimeInterval(interval.duration_min * 60)
                )

                // Предупреждение — пульсовая зона
                let hrAlert = HeartRateRangeAlert(
                    target: HKQuantity(
                        unit: .count().unitDivided(by: .minute()),
                        doubleValue: Double((zone.min + min(zone.max, 220)) / 2)
                    ),
                    minimum: HKQuantity(
                        unit: .count().unitDivided(by: .minute()),
                        doubleValue: Double(zone.min)
                    ),
                    maximum: HKQuantity(
                        unit: .count().unitDivided(by: .minute()),
                        doubleValue: Double(min(zone.max, 220))
                    )
                )

                let step = WorkoutStep(
                    goal: goal,
                    displayName: interval.note,
                    alert: hrAlert
                )
                steps.append(.step(step))
            }

            guard !steps.isEmpty else {
                lastError = "Нет отрезков для создания тренировки"
                return false
            }

            // Создаём план
            let activityConfig = WorkoutActivityConfiguration(
                activityType: workout.activityType,
                locationType: workout.sport == "bike" ? .outdoor : .outdoor,
                swimmingLocationType: workout.sport == "swim" ? .openWater : nil
            )

            let composition = WorkoutComposition(
                steps: steps
            )

            let plan = CustomWorkout(
                activity: activityConfig,
                displayName: workout.title,
                warmup: nil,
                blocks: [WorkoutBlock(steps: steps, iterations: 1)],
                cooldown: nil
            )

            // Сохраняем через WorkoutKit
            try await WorkoutKit.shared.save(plan)

            // Запоминаем как сохранённую
            savedWorkouts.append(workout.title)
            return true

        } catch {
            lastError = "Ошибка сохранения: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Save all workouts for a week

    func saveAllWorkouts(_ workouts: [WorkoutPlanJSON]) async -> (saved: Int, failed: Int) {
        var saved = 0
        var failed = 0

        let trainable = workouts.filter { $0.sport != "rest" && $0.sport != "mobility" }

        for workout in trainable {
            let success = await saveWorkout(workout)
            if success { saved += 1 } else { failed += 1 }
        }
        return (saved, failed)
    }

    // MARK: - Check if already saved

    func isAlreadySaved(_ title: String) -> Bool {
        savedWorkouts.contains(title)
    }

    // MARK: - Load existing plans from WorkoutKit

    func loadSavedPlans() async {
        do {
            let plans = try await WorkoutKit.shared.workoutPlans
            savedWorkouts = plans.compactMap { plan in
                if case let .custom(custom) = plan {
                    return custom.displayName
                }
                return nil
            }
        } catch {
            // Нет сохранённых или ошибка — не критично
        }
    }
}

// MARK: - Fallback для iOS < 17

// Если WorkoutKit недоступен, используем HKWorkout напрямую
class LegacyWorkoutSaver {
    static func saveAsHealthKitWorkout(_ workout: WorkoutPlanJSON) async throws {
        let store = HKHealthStore()
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(TimeInterval(workout.duration_min * 60))

        let hkWorkout = HKWorkout(
            activityType: workout.activityType,
            start: startDate,
            end: endDate
        )

        try await store.save(hkWorkout)
    }
}
