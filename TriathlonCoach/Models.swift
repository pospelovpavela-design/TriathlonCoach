import Foundation
import HealthKit

// MARK: - JSON Models

struct WorkoutPlanJSON: Codable, Identifiable {
    var id: UUID = UUID()
    let title: String
    let sport: String
    let date: String
    let duration_min: Int
    let target_zone: String
    let description: String
    let intervals: [IntervalJSON]
    let tags: [String]
    let rpe_target: Int?
    let planned: Bool
    var completed: Bool
    var actual_avg_hr: Int?
    var actual_duration_min: Int?
    var notes_after: String

    // Recovery & wellness metrics (logged after workout)
    var hrv_before: Int?
    var hrv_after: Int?
    var spo2_percent: Double?
    var hr_recovery_60s: Int?
    var rpe_actual: Int?
    var sleep_hours: Double?
    var sleep_quality: Int?   // 1–5
    var resting_hr: Int?      // утренний пульс покоя (уд/мин)
    var sleep_avg_hr: Int?    // средний пульс во сне (уд/мин)
    var actual_max_hr: Int?
    var actual_distance_m: Double?
    var actual_calories: Int?
    var actual_intervals: [ActualInterval]?
    var sleep_deep_hours: Double?
    var sleep_rem_hours: Double?
    var sleep_core_hours: Double?
    var sleep_avg_hrv: Double?

    enum CodingKeys: String, CodingKey {
        case title, sport, date, duration_min, target_zone, description
        case intervals, tags, rpe_target, planned, completed
        case actual_avg_hr, actual_duration_min, notes_after
        case hrv_before, hrv_after, spo2_percent, hr_recovery_60s
        case rpe_actual, sleep_hours, sleep_quality
        case resting_hr, sleep_avg_hr
        case actual_max_hr, actual_distance_m, actual_calories, actual_intervals
        case sleep_deep_hours, sleep_rem_hours, sleep_core_hours, sleep_avg_hrv
    }
}

struct IntervalJSON: Codable, Identifiable {
    var id: UUID = UUID()
    let duration_min: Int
    let zone: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case duration_min, zone, note
    }
}

struct ActualInterval: Codable {
    var number: Int
    var duration_min: Double
    var avg_hr: Int?
    var max_hr: Int?
    var distance_m: Double?

    nonisolated var pace_sec_per_km: Double? {
        guard let d = distance_m, d > 0 else { return nil }
        return (duration_min * 60) / (d / 1000)
    }
    nonisolated var speed_kmh: Double? {
        guard let d = distance_m, duration_min > 0 else { return nil }
        return (d / 1000) / (duration_min / 60)
    }
    nonisolated var paceString: String? {
        guard let p = pace_sec_per_km else { return nil }
        return String(format: "%d:%02d /км", Int(p) / 60, Int(p) % 60)
    }
    nonisolated var speedString: String? {
        guard let s = speed_kmh else { return nil }
        return String(format: "%.1f км/ч", s)
    }
}

// MARK: - Пульсовые зоны

struct HRZone {
    let key: String
    let name: String
    let min: Int
    let max: Int
    let color: String

    var hrRange: ClosedRange<Double> {
        Double(min)...Double(Swift.min(max, 220))
    }

    static let zones: [String: HRZone] = [
        "Z1": HRZone(key: "Z1", name: "Восстановительная", min: 0,   max: 119, color: "green"),
        "Z2": HRZone(key: "Z2", name: "Аэробная база",     min: 120, max: 145, color: "blue"),
        "Z3": HRZone(key: "Z3", name: "Аэробный порог",    min: 146, max: 163, color: "yellow"),
        "Z4": HRZone(key: "Z4", name: "Анаэробный порог",  min: 164, max: 175, color: "orange"),
        "Z5": HRZone(key: "Z5", name: "Максимум",          min: 176, max: 220, color: "red"),
    ]

    static func zone(for key: String) -> HRZone? { zones[key] }

    var displayRange: String {
        if max >= 220 { return ">\(min) уд/мин" }
        return "\(min)–\(max) уд/мин"
    }
}

// MARK: - Logged workout (raw HKWorkout from Apple Health)

struct LoggedWorkout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var sport: String              // mapped to our sport keys (or "walk"/"hike"/"rowing"/"other")
    var date: String               // yyyy-MM-dd of startTime (local tz)
    var startTimeISO: String       // ISO8601 — stable identity for dedup
    var durationMin: Double
    var avgHR: Int?
    var maxHR: Int?
    var distanceM: Double?
    var calories: Int?
    var sourceName: String?        // "Apple Watch", "Strava", "Garmin Connect", ...

    enum CodingKeys: String, CodingKey {
        case id, sport, date, startTimeISO, durationMin, avgHR, maxHR, distanceM, calories, sourceName
    }

    var startDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: startTimeISO)
    }

    var startTimeLabel: String {
        guard let d = startDate else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    var paceSecPerKm: Double? {
        guard let d = distanceM, d > 0, durationMin > 0 else { return nil }
        return (durationMin * 60) / (d / 1000)
    }
    var speedKmh: Double? {
        guard let d = distanceM, durationMin > 0 else { return nil }
        return (d / 1000) / (durationMin / 60)
    }
    var paceString: String? {
        guard let p = paceSecPerKm else { return nil }
        return String(format: "%d:%02d /км", Int(p) / 60, Int(p) % 60)
    }
    var speedString: String? {
        guard let s = speedKmh else { return nil }
        return String(format: "%.1f км/ч", s)
    }
    var distanceString: String? {
        guard let d = distanceM, d > 0 else { return nil }
        return d >= 1000
            ? String(format: "%.2f км", d / 1000)
            : String(format: "%.0f м", d)
    }
}

// MARK: - Health Day Entry

struct HealthDayEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String  // yyyy-MM-dd

    // Biometrics
    var hrv: Int?
    var restingHR: Int?
    var spo2: Double?
    var wristTemperatureDelta: Double?  // °C deviation from personal baseline
    var weight: Double?                 // kg
    var systolicBP: Int?
    var diastolicBP: Int?

    // Sleep
    var sleepHours: Double?
    var sleepQuality: Int?        // 1–5
    var sleepDeepHours: Double?
    var sleepRemHours: Double?
    var sleepCoreHours: Double?
    var sleepAvgHR: Int?
    var sleepAvgHRV: Double?

    // Nutrition (consumed that day)
    var caloriesConsumed: Int?
    var proteinG: Double?
    var fatG: Double?
    var carbsG: Double?

    // Cardio fitness & recovery
    var respiratoryRate: Double?      // BrPM, overnight avg
    var vo2max: Double?               // ml/(kg·min), latest
    var cardioRecovery: Int?          // bpm drop 1 min after high-intensity (Apple)
    var walkingHR: Double?            // bpm, latest

    // Daily activity rings
    var steps: Int?
    var standMin: Int?
    var exerciseMin: Int?

    // Mindfulness
    var mindfulMin: Int?
    var mindfulSessions: Int?

    // Training load (iOS 18+)
    var workoutEffort: Double?        // workoutEffortScore, latest

    // State of Mind / mood (iOS 18+)
    var moodValence: Double?          // −1..+1
    var moodLabels: [String]?
    var moodKind: String?             // "momentaryEmotion" / "dailyMood"

    // Notes
    var notes: String?

    // AI readiness analysis
    var aiReadinessScore: Int?     // 0–100
    var aiStatus: String?          // "отличное"/"хорошее"/"удовлетворительное"/"плохое"
    var aiSummary: String?
    var aiTrainingRec: String?
    var aiNutritionRec: String?
    var aiRecoveryRec: String?
    var aiWarnings: [String]?
    var aiGeneratedAt: String?     // yyyy-MM-dd HH:mm

    var parsedDate: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }
    var formattedDate: String {
        guard let d = parsedDate else { return date }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEE, d MMM"
        return f.string(from: d).capitalized
    }
    var isToday: Bool {
        guard let d = parsedDate else { return false }
        return Calendar.current.isDateInToday(d)
    }
    var hasData: Bool {
        hrv != nil || restingHR != nil || weight != nil || sleepHours != nil || caloriesConsumed != nil
            || respiratoryRate != nil || vo2max != nil || steps != nil || mindfulMin != nil || moodValence != nil
    }
    var hasAIAnalysis: Bool { aiReadinessScore != nil }
}

// MARK: - Sport mapping

extension WorkoutPlanJSON {
    var activityType: HKWorkoutActivityType {
        switch sport {
        case "run":         return .running
        case "bike":        return .cycling
        case "swim":        return .swimming
        case "strength":    return .traditionalStrengthTraining
        case "mobility":    return .flexibility
        case "bike_indoor": return .cycling
        case "run_indoor":  return .running
        case "core":        return .coreTraining
        case "stretch":     return .flexibility
        default:            return .other
        }
    }

    var sportIcon: String {
        switch sport {
        case "run":         return "figure.run"
        case "bike":        return "figure.outdoor.cycle"
        case "swim":        return "figure.pool.swim"
        case "strength":    return "dumbbell"
        case "mobility":    return "figure.flexibility"
        case "bike_indoor": return "figure.indoor.cycle"
        case "run_indoor":  return "figure.run.treadmill"
        case "core":        return "figure.core.training"
        case "stretch":     return "figure.flexibility"
        case "rest":        return "moon.zzz"
        default:            return "heart"
        }
    }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(date.prefix(10)))
    }

    var stableKey: String { title + date }

    nonisolated var plannedIntervalMinutes: Int {
        intervals.reduce(0) { $0 + $1.duration_min }
    }

    nonisolated var actualIntervalMinutes: Double? {
        guard let actualIntervals = actual_intervals, !actualIntervals.isEmpty else { return nil }
        return actualIntervals.reduce(0.0) { $0 + $1.duration_min }
    }

    nonisolated var extraMinutesAfterPlannedTarget: Int? {
        guard let actual = actual_duration_min else { return nil }
        let target = plannedIntervalMinutes > 0 ? plannedIntervalMinutes : duration_min
        let extra = actual - target
        return extra > 0 ? extra : nil
    }

    nonisolated var actualSummaryForPrompt: String {
        var parts: [String] = []
        if let actual = actual_duration_min {
            parts.append("факт всего \(actual) мин")
            parts.append("плановая цель \(duration_min) мин")
        } else {
            parts.append("план \(duration_min) мин")
        }
        if plannedIntervalMinutes > 0 && plannedIntervalMinutes != duration_min {
            parts.append("интервалы по плану \(plannedIntervalMinutes) мин")
        }
        if let actualIntervals = actualIntervalMinutes {
            parts.append(String(format: "сегменты Apple Fitness %.1f мин", actualIntervals))
        }
        if let extra = extraMinutesAfterPlannedTarget {
            parts.append("+\(extra) мин сверх плановой цели: считать отдельной заминкой/ходьбой/растяжкой, если это подтверждается пульсом, интервалами или заметками")
        }
        return parts.joined(separator: ", ")
    }

    nonisolated var actualDetailLinesForPrompt: [String] {
        var lines: [String] = []
        if let extra = extraMinutesAfterPlannedTarget {
            let target = plannedIntervalMinutes > 0 ? plannedIntervalMinutes : duration_min
            lines.append("   разбор длительности: целевой блок \(target) мин; дополнительно \(extra) мин после цели. Не трактуй эти \(extra) мин как превышение интенсивного задания без подтверждения по пульсу/интервалам.")
        }
        if let actualIntervals = actual_intervals, !actualIntervals.isEmpty {
            let details = actualIntervals.prefix(8).map { iv -> String in
                var line = "\(iv.number): \(String(format: "%.1f", iv.duration_min))м"
                if let hr = iv.avg_hr { line += " срЧСС \(hr)" }
                if let max = iv.max_hr { line += "/макс \(max)" }
                if let pace = iv.paceString { line += " \(pace)" }
                else if let speed = iv.speedString { line += " \(speed)" }
                return line
            }.joined(separator: "; ")
            let suffix = actualIntervals.count > 8 ? "; ..." : ""
            lines.append("   сегменты Apple Fitness: \(details)\(suffix)")
        }
        return lines
    }

    var isToday: Bool {
        guard let d = parsedDate else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var formattedDate: String {
        guard let d = parsedDate else { return date }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEE, d MMM"
        return f.string(from: d).capitalized
    }
}
