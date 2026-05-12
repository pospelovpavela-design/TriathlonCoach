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
        coaching: CoachingProfile = CoachingProfile(),
        requestText: String,
        healthEntry: HealthDayEntry? = nil,
        readiness: HealthService.LocalReadiness? = nil,
        todayWorkouts: [WorkoutPlanJSON] = [],
        yesterdayWorkouts: [WorkoutPlanJSON] = [],
        tomorrowWorkouts: [WorkoutPlanJSON] = [],
        weeklyWorkouts: [WorkoutPlanJSON] = [],
        todayLogged: [LoggedWorkout] = [],
        yesterdayLogged: [LoggedWorkout] = [],
        tomorrowLogged: [LoggedWorkout] = [],
        weeklyLogged: [LoggedWorkout] = [],
        preferences: String = ""
    ) -> String {
        var lines: [String] = []
        lines.append("\(coaching.coachIntro()) \(requestText)")
        lines.append("")

        if let m = coaching.methodologyBlock() {
            lines.append("## Методика подготовки")
            lines.append(m)
            lines.append("")
        }

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

        if let h = healthEntry, h.hasAIAnalysis {
            lines.append("## AI-анализ готовности (из вкладки «Здоровье»)")
            if let s = h.aiReadinessScore { lines.append("**Готовность:** \(s)/100\(h.aiStatus.map { " — \($0)" } ?? "")") }
            if let s = h.aiSummary,      !s.isEmpty { lines.append("**Резюме:** \(s)") }
            if let s = h.aiTrainingRec,  !s.isEmpty { lines.append("**Рек. по тренировке:** \(s)") }
            if let s = h.aiRecoveryRec,  !s.isEmpty { lines.append("**Рек. по восстановлению:** \(s)") }
            if let s = h.aiNutritionRec, !s.isEmpty { lines.append("**Рек. по питанию:** \(s)") }
            if let w = h.aiWarnings, !w.isEmpty {
                lines.append("**Предупреждения:**")
                for x in w { lines.append("• \(x)") }
            }
            if let ts = h.aiGeneratedAt { lines.append("_(сгенерировано: \(ts))_") }
            lines.append("")
        }

        if !yesterdayWorkouts.isEmpty || !yesterdayLogged.isEmpty {
            lines.append("## Вчера — факт тренировки")
            appendWorkoutContext(
                to: &lines,
                workouts: yesterdayWorkouts,
                logged: yesterdayLogged,
                includePending: false,
                emptyLoggedTitle: "**Из Apple Health (без плана):**"
            )
            lines.append("")
        }

        if !weeklyWorkouts.isEmpty || !weeklyLogged.isEmpty {
            let s = HealthService.weekLoadSummary(weeklyWorkouts, loggedWorkouts: weeklyLogged)
            lines.append("## Тренировочная нагрузка — последние 7 дней")
            if s.plannedCount > 0 {
                lines.append("• Выполнено: \(s.doneCount)/\(s.plannedCount) тренировок (\(Int(s.completionPct))%)")
            }
            if s.actualMin > 0 {
                lines.append("• Объём факт: \(s.actualMin) мин (\(s.actualMin / 60)ч \(s.actualMin % 60)м), план \(s.plannedMin) мин")
            } else if s.plannedMin > 0 {
                lines.append("• Объём план: \(s.plannedMin) мин")
            }
            if s.restDays > 0 { lines.append("• Дней отдыха: \(s.restDays)") }
            for row in s.bySport {
                lines.append("• \(ReportBuilder.sportEmoji(row.sport)) \(ReportBuilder.sportName(row.sport)): \(row.promptDetail)")
            }
            if let hr = s.avgHR { lines.append("• Средний ЧСС в выполненных: \(hr) уд/мин") }
            if let rpe = s.avgRPE { lines.append("• Средний RPE: \(String(format: "%.1f", rpe))/10") }
            lines.append("")
        }

        if !todayWorkouts.isEmpty || !todayLogged.isEmpty {
            lines.append("## Сегодня — план и факт")
            appendWorkoutContext(
                to: &lines,
                workouts: todayWorkouts,
                logged: todayLogged,
                includePending: true,
                emptyLoggedTitle: "**Из Apple Health (без плана):**"
            )
            lines.append("")
        }

        if !tomorrowWorkouts.isEmpty || !tomorrowLogged.isEmpty {
            lines.append("## Завтра — плановый контекст")
            appendWorkoutContext(
                to: &lines,
                workouts: tomorrowWorkouts,
                logged: tomorrowLogged,
                includePending: true,
                emptyLoggedTitle: "**Apple Health на завтра (если есть):**"
            )
            lines.append("Используй завтрашний план как ограничение: сегодняшняя коррекция должна помогать целевому плану, а не ломать нагрузку завтра.")
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

    private static func appendWorkoutContext(
        to lines: inout [String],
        workouts: [WorkoutPlanJSON],
        logged: [LoggedWorkout],
        includePending: Bool,
        emptyLoggedTitle: String
    ) {
        for w in workouts {
            if !includePending && !w.completed && w.sport != "rest" { continue }

            let mark = w.completed ? "✅" : (w.sport == "rest" ? "😴" : "⬜")
            var line = "• \(ReportBuilder.sportEmoji(w.sport)) \(mark) \(w.title) — план \(w.duration_min) мин, цель \(w.target_zone)"
            if let rpe = w.rpe_target { line += ", RPE \(rpe)/10" }
            lines.append(line)

            if w.completed {
                var fact: [String] = [w.actualSummaryForPrompt]
                if let hr = w.actual_avg_hr {
                    var s = "ср. ЧСС \(hr)"
                    if let mx = w.actual_max_hr { s += "/макс \(mx)" }
                    fact.append(s)
                }
                if let d = w.actual_distance_m, d > 0 {
                    fact.append(d >= 1000 ? String(format: "%.2f км", d / 1000) : String(format: "%.0f м", d))
                }
                if let rpe = w.rpe_actual { fact.append("RPE \(rpe)/10") }
                if let cal = w.actual_calories { fact.append("\(cal) ккал") }
                lines.append("   факт: \(fact.joined(separator: ", "))")
                lines.append(contentsOf: w.actualDetailLinesForPrompt)
                if !w.notes_after.isEmpty { lines.append("   заметки: \(w.notes_after)") }
            }

            if !w.intervals.isEmpty {
                let intervals = w.intervals.map { "\($0.duration_min)м\($0.zone)" }.joined(separator: " → ")
                lines.append("   интервалы: \(intervals)")
            }
        }

        let completedSports = Set(workouts.filter { $0.completed }.map { HealthService.canonicalSport($0.sport) })
        let extraLogged = logged.filter { !completedSports.contains(HealthService.canonicalSport($0.sport)) }
        if !extraLogged.isEmpty {
            lines.append(emptyLoggedTitle)
            for lw in extraLogged {
                lines.append(loggedWorkoutLine(lw))
            }
        }
    }

    private static func loggedWorkoutLine(_ lw: LoggedWorkout) -> String {
        var parts: [String] = ["\(Int(lw.durationMin.rounded())) мин"]
        if let hr = lw.avgHR {
            var s = "ср. ЧСС \(hr)"
            if let mx = lw.maxHR { s += "/макс \(mx)" }
            parts.append(s)
        }
        if let s = lw.distanceString { parts.append(s) }
        if let cal = lw.calories { parts.append("\(cal) ккал") }
        if !lw.startTimeLabel.isEmpty { parts.append(lw.startTimeLabel) }
        if let src = lw.sourceName { parts.append("источник: \(src)") }
        return "• \(ReportBuilder.sportEmoji(lw.sport)) 🟦 \(ReportBuilder.sportName(lw.sport)) — \(parts.joined(separator: ", "))"
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
