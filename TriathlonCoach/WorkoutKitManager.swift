import Foundation
import Combine
import WorkoutKit
import HealthKit

// MARK: - WorkoutKit Manager
// Requires iOS 17+ / watchOS 10+

@MainActor
class WorkoutKitManager: ObservableObject {

    @Published var authorizationStatus: AuthStatus = .unknown
    @Published var savedWorkouts: [String] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let indoorSports: Set<String> = ["bike_indoor", "run_indoor", "strength", "core"]

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
        guard WorkoutScheduler.isSupported else {
            authorizationStatus = .denied
            lastError = "WorkoutKit недоступен (нет Apple Watch в паре)"
            return
        }

        let state = await WorkoutScheduler.shared.requestAuthorization()
        switch state {
        case .authorized:
            authorizationStatus = .authorized
            lastError = nil
        case .denied:
            authorizationStatus = .denied
            lastError = "WorkoutKit: доступ запрещён пользователем"
        case .restricted:
            authorizationStatus = .denied
            lastError = "WorkoutKit: доступ ограничен системой"
        case .notDetermined:
            authorizationStatus = .unknown
            lastError = "WorkoutKit: ожидает разрешения"
        @unknown default:
            authorizationStatus = .unknown
            lastError = "WorkoutKit: неизвестный статус \(state.rawValue)"
        }
    }

    // MARK: - Save workout plan to Watch

    func saveWorkout(_ workout: WorkoutPlanJSON) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        guard workout.sport != "rest", workout.sport != "mobility", workout.sport != "stretch" else {
            lastError = "Тренировки типа 'отдых/растяжка' не добавляются на часы"
            return false
        }

        let activityType = workout.activityType
        let location: HKWorkoutSessionLocationType = indoorSports.contains(workout.sport) ? .indoor : .outdoor

        guard CustomWorkout.supportsActivity(activityType) else {
            lastError = "Тип тренировки «\(workout.sport)» не поддерживается WorkoutKit на часах"
            return false
        }

        var intervalSteps: [IntervalStep] = []

        for interval in workout.intervals {
            guard interval.duration_min > 0 else { continue }
            guard let zone = HRZone.zone(for: interval.zone) else { continue }

            let goal = WorkoutGoal.time(Double(interval.duration_min) * 60, .seconds)

            let minHR = max(Double(zone.min), 40.0)
            let maxHR = max(Double(min(zone.max, 220)), minHR + 1.0)
            let hrAlert: HeartRateRangeAlert = .heartRate(minHR...maxHR)

            let alertSupported = CustomWorkout.supportsAlert(
                hrAlert, activity: activityType, location: location
            )
            let step = WorkoutStep(
                goal: goal,
                alert: alertSupported ? hrAlert : nil,
                displayName: interval.note.isEmpty ? nil : interval.note
            )
            intervalSteps.append(IntervalStep(.work, step: step))
        }

        guard !intervalSteps.isEmpty else {
            lastError = "Нет отрезков для создания тренировки"
            return false
        }

        let block = IntervalBlock(steps: intervalSteps, iterations: 1)
        let customWorkout = CustomWorkout(
            activity: activityType,
            location: location,
            displayName: workout.title,
            blocks: [block]
        )
        let plan = WorkoutPlan(.custom(customWorkout))
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        await WorkoutScheduler.shared.schedule(plan, at: dateComponents)

        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        let found = scheduled.contains { s in
            if case let .custom(c) = s.plan.workout { return c.displayName == workout.title }
            return false
        }

        if found {
            savedWorkouts.append(workout.title)
            return true
        } else {
            lastError = "schedule() вызван, но тренировка «\(workout.title)» не найдена в scheduledWorkouts (всего: \(scheduled.count))"
            return false
        }
    }

    // MARK: - Save all workouts for a week

    func saveAllWorkouts(_ workouts: [WorkoutPlanJSON]) async -> (saved: Int, failed: Int) {
        var saved = 0
        var failed = 0
        let trainable = workouts.filter { $0.sport != "rest" && $0.sport != "mobility" && $0.sport != "stretch" }
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
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        savedWorkouts = scheduled.compactMap { scheduledPlan in
            if case let .custom(custom) = scheduledPlan.plan.workout {
                return custom.displayName
            }
            return nil
        }
    }
}
