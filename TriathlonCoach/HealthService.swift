import Foundation

struct HealthService {

    // MARK: - Prompt Builder

    static func buildPrompt(entry: HealthDayEntry, profile: AthleteProfile, plannedWorkouts: [WorkoutPlanJSON]) -> String {
        var lines: [String] = []
        lines.append("Ты — врач спортивной медицины и тренер по триатлону.")
        lines.append("")
        lines.append("## Состояние здоровья атлета")
        lines.append("**Дата:** \(entry.formattedDate)")
        lines.append("**Атлет:** \(profile.name), макс. ЧСС \(profile.maxHR) уд/мин, пульс покоя \(profile.restingHR) уд/мин")
        if !profile.notes.isEmpty { lines.append("**О себе:** \(profile.notes)") }
        lines.append("")

        lines.append("### Биометрика")
        var hasAny = false
        if let v = entry.hrv               { lines.append("• HRV утренний: \(v) мс"); hasAny = true }
        if let v = entry.restingHR         { lines.append("• Пульс покоя: \(v) уд/мин"); hasAny = true }
        if let v = entry.spo2              { lines.append("• SpO2: \(Int(v))%"); hasAny = true }
        if let v = entry.wristTemperatureDelta {
            let sign = v >= 0 ? "+" : ""
            lines.append("• Температура запястья (отклонение): \(sign)\(String(format: "%.2f", v))°C"); hasAny = true
        }
        if let v = entry.weight            { lines.append("• Вес: \(String(format: "%.1f", v)) кг"); hasAny = true }
        if let s = entry.systolicBP, let d = entry.diastolicBP {
            lines.append("• Давление: \(s)/\(d) мм рт.ст."); hasAny = true
        }
        if !hasAny { lines.append("• (нет данных)") }
        lines.append("")

        lines.append("### Сон (прошлая ночь)")
        if let h = entry.sleepHours {
            var sl = "• Общее: \(String(format: "%.1f", h)) ч"
            if let d = entry.sleepDeepHours { sl += ", глубокий \(String(format: "%.1f", d)) ч" }
            if let r = entry.sleepRemHours  { sl += ", REM \(String(format: "%.1f", r)) ч" }
            if let c = entry.sleepCoreHours { sl += ", Core \(String(format: "%.1f", c)) ч" }
            lines.append(sl)
        }
        if let hr  = entry.sleepAvgHR  { lines.append("• Пульс во сне: \(hr) уд/мин") }
        if let hrv = entry.sleepAvgHRV { lines.append("• HRV во сне: \(Int(hrv)) мс") }
        if let q   = entry.sleepQuality { lines.append("• Качество сна: \(q)/5") }
        if entry.sleepHours == nil      { lines.append("• (нет данных)") }
        lines.append("")

        let hasNutrition = entry.caloriesConsumed != nil || entry.proteinG != nil
        if hasNutrition {
            lines.append("### Питание (предыдущий день)")
            if let v = entry.caloriesConsumed { lines.append("• Калории: \(v) ккал") }
            var macros: [String] = []
            if let v = entry.proteinG { macros.append("белки \(String(format: "%.0f", v)) г") }
            if let v = entry.fatG     { macros.append("жиры \(String(format: "%.0f", v)) г") }
            if let v = entry.carbsG   { macros.append("углеводы \(String(format: "%.0f", v)) г") }
            if !macros.isEmpty { lines.append("• Макронутриенты: \(macros.joined(separator: ", "))") }
            lines.append("")
        }

        if !plannedWorkouts.isEmpty {
            lines.append("### Тренировки запланированы на сегодня")
            for w in plannedWorkouts {
                lines.append("• [\(w.sport.uppercased())] \(w.title) — \(w.duration_min) мин, зона \(w.target_zone)")
            }
            lines.append("")
        }

        if let notes = entry.notes, !notes.isEmpty {
            lines.append("### Заметки атлета")
            lines.append(notes)
            lines.append("")
        }

        lines.append("---")
        lines.append("Проанализируй состояние и готовность к тренировкам. Верни **только** JSON-блок:")
        lines.append("")
        lines.append("```json")
        lines.append("{")
        lines.append("  \"date\": \"\(entry.date)\",")
        lines.append("  \"readiness_score\": <целое 0-100>,")
        lines.append("  \"status\": \"<отличное|хорошее|удовлетворительное|плохое>\",")
        lines.append("  \"summary\": \"<2-3 предложения об общем состоянии>\",")
        lines.append("  \"training_rec\": \"<рекомендация по тренировке сегодня>\",")
        lines.append("  \"nutrition_rec\": \"<рекомендация по питанию>\",")
        lines.append("  \"recovery_rec\": \"<рекомендация по восстановлению>\",")
        lines.append("  \"warnings\": []")
        lines.append("}")
        lines.append("```")

        return lines.joined(separator: "\n")
    }

    // MARK: - Response Parser

    struct AIAnalysis {
        let score: Int
        let status: String
        let summary: String
        let trainingRec: String
        let nutritionRec: String
        let recoveryRec: String
        let warnings: [String]
    }

    static func parseAIResponse(_ text: String) -> AIAnalysis? {
        let jsonString: String
        if let start = text.range(of: "```json"),
           let end   = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            jsonString = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let start = text.firstIndex(of: "{"),
                  let end   = text.lastIndex(of: "}") {
            jsonString = String(text[start...end])
        } else { return nil }

        guard let data = jsonString.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let score = obj["readiness_score"] as? Int else { return nil }
        return AIAnalysis(
            score:       score,
            status:      obj["status"]        as? String ?? "",
            summary:     obj["summary"]       as? String ?? "",
            trainingRec: obj["training_rec"]  as? String ?? "",
            nutritionRec:obj["nutrition_rec"] as? String ?? "",
            recoveryRec: obj["recovery_rec"]  as? String ?? "",
            warnings:    obj["warnings"]      as? [String] ?? []
        )
    }

    // MARK: - Readiness color

    static func readinessColor(score: Int?) -> (r: Double, g: Double, b: Double) {
        guard let s = score else { return (0.5, 0.5, 0.5) }
        if s >= 80 { return (0.13, 0.77, 0.37) }   // green
        if s >= 60 { return (0.92, 0.70, 0.03) }   // yellow
        if s >= 40 { return (0.98, 0.45, 0.09) }   // orange
        return (0.94, 0.27, 0.27)                   // red
    }
}
