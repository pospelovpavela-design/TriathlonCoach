import Foundation

// MARK: - Chat Message (kept for compatibility)

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: String
    var content: String
}

// MARK: - Service (prompt building + JSON parsing)

actor ClaudeService {

    static let shared = ClaudeService()

    // MARK: - Copyable prompt builder

    static func buildCopyablePrompt(
        profile: AthleteProfile,
        requestText: String,
        healthEntry: HealthDayEntry? = nil,
        readiness: HealthService.LocalReadiness? = nil,
        todayWorkouts: [WorkoutPlanJSON] = [],
        preferences: String = ""
    ) -> String {
        var lines: [String] = []
        lines.append("Ты — профессиональный тренер по триатлону. \(requestText)")
        lines.append("")
        lines.append("## Профиль атлета")
        lines.append(profile.claudeContext)
        lines.append("")

        if let h = healthEntry, h.hasData {
            lines.append("## Сегодня — состояние организма (\(h.formattedDate))")
            if let v = h.hrv               { lines.append("• HRV утренний: \(v) мс") }
            if let v = h.restingHR         { lines.append("• Пульс покоя: \(v) уд/мин") }
            if let v = h.spo2              { lines.append("• SpO2: \(Int(v))%") }
            if let v = h.wristTemperatureDelta {
                let sign = v >= 0 ? "+" : ""
                lines.append("• Темп. запястья (Δ): \(sign)\(String(format: "%.2f", v))°C")
            }
            if let v = h.vo2max            { lines.append("• VO₂max: \(String(format: "%.1f", v)) мл/(кг·мин)") }
            if let v = h.cardioRecovery    { lines.append("• Кардио-восст. 1 мин: −\(v) уд/мин") }
            if let v = h.respiratoryRate   { lines.append("• ЧД ночь: \(String(format: "%.1f", v)) /мин") }
            if let h2 = h.sleepHours {
                var s = "• Сон: \(String(format: "%.1f", h2)) ч"
                if let d = h.sleepDeepHours { s += ", глубокий \(String(format: "%.1f", d)) ч" }
                if let r = h.sleepRemHours  { s += ", REM \(String(format: "%.1f", r)) ч" }
                if let q = h.sleepQuality   { s += ", качество \(q)/5" }
                lines.append(s)
            }
            if let v = h.steps             { lines.append("• Шаги: \(v)") }
            if let m = h.mindfulMin {
                let suf = h.mindfulSessions.map { ", \($0) сесс." } ?? ""
                lines.append("• Осознанность: \(m) мин\(suf)")
            }
            if let v = h.moodValence {
                var line = "• Настроение: valence \(String(format: "%+.2f", v))"
                if let l = h.moodLabels, !l.isEmpty { line += " (\(l.joined(separator: ", ")))" }
                lines.append(line)
            }
            lines.append("")
        }

        if let r = readiness {
            lines.append("## Локальный Readiness (из HK)")
            lines.append("**Скор:** \(r.score)/100 — \(r.status)")
            if !r.warnings.isEmpty {
                lines.append("**Red flags:**")
                for w in r.warnings { lines.append("• \(w)") }
            }
            if !r.components.isEmpty {
                lines.append("**Разбор:**")
                for c in r.components {
                    let sign = c.delta > 0 ? "+\(c.delta)" : "\(c.delta)"
                    lines.append("• \(c.label): \(c.detail) → \(sign)")
                }
            }
            lines.append("")
        }

        if !todayWorkouts.isEmpty {
            lines.append("## Запланировано на сегодня")
            for w in todayWorkouts {
                var line = "• [\(w.sport.uppercased())] \(w.title) — \(w.duration_min) мин, цель \(w.target_zone)"
                if let rpe = w.rpe_target { line += ", RPE \(rpe)/10" }
                if w.completed { line += " ✓ выполнено" }
                lines.append(line)
                if !w.intervals.isEmpty {
                    let ints = w.intervals.map { "\($0.duration_min)м\($0.zone)" }.joined(separator: " → ")
                    lines.append("   интервалы: \(ints)")
                }
            }
            lines.append("")
        }

        let prefs = preferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefs.isEmpty {
            lines.append("## Пожелания и возможности на сегодня")
            lines.append(prefs)
            lines.append("")
        }

        lines.append("## Пульсовые зоны")
        lines.append("• Z1: до 119 уд/мин — восстановление")
        lines.append("• Z2: 120–145 уд/мин — аэробная база")
        lines.append("• Z3: 146–163 уд/мин — аэробный порог")
        lines.append("• Z4: 164–175 уд/мин — анаэробный порог")
        lines.append("• Z5: 176+ уд/мин — максимум")
        lines.append("")

        lines.append("Виды спорта (только эти значения в поле \"sport\"): run, bike, swim, strength, mobility, rest, bike_indoor, run_indoor, core, stretch")
        lines.append("")

        lines.append("ВАЖНО: В ответе обязательно включи JSON-блок строго в таком формате:")
        lines.append("```json")
        lines.append("[")
        lines.append("  {")
        lines.append("    \"title\": \"Название тренировки\",")
        lines.append("    \"sport\": \"run\",")
        lines.append("    \"date\": \"yyyy-MM-dd\",")
        lines.append("    \"duration_min\": 45,")
        lines.append("    \"target_zone\": \"Z2\",")
        lines.append("    \"description\": \"Описание тренировки\",")
        lines.append("    \"intervals\": [")
        lines.append("      {\"duration_min\": 10, \"zone\": \"Z1\", \"note\": \"Разминка\"},")
        lines.append("      {\"duration_min\": 30, \"zone\": \"Z2\", \"note\": \"Основная часть\"},")
        lines.append("      {\"duration_min\": 5, \"zone\": \"Z1\", \"note\": \"Заминка\"}")
        lines.append("    ],")
        lines.append("    \"tags\": [\"run\", \"z2\"],")
        lines.append("    \"rpe_target\": 6,")
        lines.append("    \"planned\": true,")
        lines.append("    \"completed\": false,")
        lines.append("    \"actual_avg_hr\": null,")
        lines.append("    \"actual_duration_min\": null,")
        lines.append("    \"notes_after\": \"\"")
        lines.append("  }")
        lines.append("]")
        lines.append("```")
        lines.append("Отвечай на русском языке.")

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON extraction

    func extractWorkouts(from text: String) -> [WorkoutPlanJSON] {
        if let json = Self.extractFromCodeFence(text),
           let workouts = Self.decode(json) { return workouts }
        if let start = text.firstIndex(of: "["),
           let end = text.lastIndex(of: "]") {
            let jsonStr = String(text[start...end])
            if let workouts = Self.decode(jsonStr) { return workouts }
        }
        return []
    }

    /// A workout the model asked the app to remove.
    struct DeleteRequest: Equatable {
        let title: String
        let date: String   // yyyy-MM-dd
    }

    /// Parse `УДАЛИТЬ: "<title>" "<yyyy-MM-dd>"` lines from Claude's text reply.
    static func extractDeletes(from text: String) -> [DeleteRequest] {
        let pattern = #"УДАЛИТЬ:\s*"([^"]+)"\s+"(\d{4}-\d{2}-\d{2})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var results: [DeleteRequest] = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges == 3 else { return }
            let title = nsText.substring(with: m.range(at: 1))
            let date  = nsText.substring(with: m.range(at: 2))
            results.append(DeleteRequest(title: title, date: date))
        }
        return results
    }

    private static func extractFromCodeFence(_ text: String) -> String? {
        guard let start = text.range(of: "```json"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ json: String) -> [WorkoutPlanJSON]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([WorkoutPlanJSON].self, from: data)
    }
}
