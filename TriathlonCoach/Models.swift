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

    enum CodingKeys: String, CodingKey {
        case title, sport, date, duration_min, target_zone, description
        case intervals, tags, rpe_target, planned, completed
        case actual_avg_hr, actual_duration_min, notes_after
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

// MARK: - Sport mapping

extension WorkoutPlanJSON {
    var activityType: HKWorkoutActivityType {
        switch sport {
        case "run":      return .running
        case "bike":     return .cycling
        case "swim":     return .swimming
        case "strength": return .traditionalStrengthTraining
        case "mobility": return .flexibility
        default:         return .other
        }
    }

    var sportIcon: String {
        switch sport {
        case "run":      return "figure.run"
        case "bike":     return "figure.outdoor.cycle"
        case "swim":     return "figure.pool.swim"
        case "strength": return "dumbbell"
        case "mobility": return "figure.flexibility"
        case "rest":     return "moon.zzz"
        default:         return "heart"
        }
    }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(date.prefix(10)))
    }

    var stableKey: String { title + date }

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
