import Foundation

struct HealthService {

    // MARK: - Prompt Builder

    static func buildPrompt(
        entry: HealthDayEntry,
        profile: AthleteProfile,
        coaching: CoachingProfile,
        dayWorkouts: [WorkoutPlanJSON],
        weeklyWorkouts: [WorkoutPlanJSON],
        dayLogged: [LoggedWorkout] = [],
        weeklyLogged: [LoggedWorkout] = []
    ) -> String {
        var lines: [String] = []
        lines.append(coaching.coachIntro())
        lines.append("Также ты — врач спортивной медицины и опираешься на физиологию спорта.")
        lines.append("")

        if let methodology = coaching.methodologyBlock() {
            lines.append("### Методика подготовки")
            lines.append(methodology)
            lines.append("")
        }

        lines.append("## Состояние здоровья атлета")
        lines.append("**Дата:** \(entry.formattedDate)")
        lines.append("**Атлет:** \(profile.name), макс. ЧСС \(profile.maxHR) уд/мин, пульс покоя \(profile.restingHR) уд/мин")
        if let lthr = profile.lactateThresholdHR {
            lines.append("**ПАНО/LTHR:** \(lthr) уд/мин; зоны от ПАНО: \(profile.thresholdZoneSummary())")
        }
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
        if let v = entry.vo2max            { lines.append("• VO₂max: \(String(format: "%.1f", v)) мл/(кг·мин)"); hasAny = true }
        if let v = entry.cardioRecovery    { lines.append("• Кардио-восст. 1 мин: −\(v) уд/мин"); hasAny = true }
        if let v = entry.walkingHR         { lines.append("• Walking HR: \(Int(v.rounded())) уд/мин"); hasAny = true }
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
        if let rr  = entry.respiratoryRate { lines.append("• Частота дыхания (ночь): \(String(format: "%.1f", rr)) /мин") }
        if let q   = entry.sleepQuality { lines.append("• Качество сна: \(q)/5") }
        if entry.sleepHours == nil      { lines.append("• (нет данных)") }
        lines.append("")

        let hasActivity = entry.steps != nil || entry.standMin != nil || entry.exerciseMin != nil
        if hasActivity {
            lines.append("### Активность за день")
            if let v = entry.steps { lines.append("• Шаги: \(v)") }
            if entry.standMin != nil || entry.exerciseMin != nil {
                var parts: [String] = []
                if let s = entry.standMin    { parts.append("стоя \(s) мин") }
                if let e = entry.exerciseMin { parts.append("движение \(e) мин") }
                lines.append("• Кольца: \(parts.joined(separator: ", "))")
            }
            lines.append("")
        }

        let hasState = entry.mindfulMin != nil || entry.workoutEffort != nil || entry.moodValence != nil
        if hasState {
            lines.append("### Состояние и нагрузка")
            if let m = entry.mindfulMin {
                let suffix = entry.mindfulSessions.map { ", \($0) сесс." } ?? ""
                lines.append("• Осознанность: \(m) мин\(suffix)")
            }
            if let e = entry.workoutEffort {
                lines.append("• Effort тренировки: \(String(format: "%.1f", e))/10")
            }
            if let v = entry.moodValence {
                let kind: String
                switch entry.moodKind {
                case "dailyMood":        kind = "дневное"
                case "momentaryEmotion": kind = "момент"
                default:                 kind = "—"
                }
                var line = "• Настроение (\(kind)): valence \(String(format: "%+.2f", v)) (диапазон −1..+1)"
                if let l = entry.moodLabels, !l.isEmpty { line += ", метки: \(l.joined(separator: ", "))" }
                lines.append(line)
            }
            lines.append("")
        }

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

        let dayCompleted = dayWorkouts.filter { $0.completed && $0.sport != "rest" }
        let dayPending   = dayWorkouts.filter { !$0.completed && $0.sport != "rest" }
        let dayRest      = dayWorkouts.filter { $0.sport == "rest" }
        if !dayWorkouts.isEmpty {
            lines.append("### Тренировки сегодня")
            if !dayCompleted.isEmpty {
                lines.append("**Выполнены:**")
                for w in dayCompleted {
                    var parts: [String] = [w.actualSummaryForPrompt]
                    if let hr = w.actual_avg_hr {
                        var s = "ср. ЧСС \(hr)"
                        if let mx = w.actual_max_hr { s += "/макс \(mx)" }
                        s += " уд/мин"
                        parts.append(s)
                    }
                    if let d = w.actual_distance_m, d > 0 {
                        parts.append(d >= 1000 ? String(format: "%.2f км", d / 1000) : String(format: "%.0f м", d))
                    }
                    if let rpe = w.rpe_actual {
                        let target = w.rpe_target.map { " (план \($0))" } ?? ""
                        parts.append("RPE \(rpe)/10\(target)")
                    }
                    if let cal = w.actual_calories { parts.append("\(cal) ккал") }
                    lines.append("• \(ReportBuilder.sportEmoji(w.sport)) ✅ \(w.title), зона \(w.target_zone) — \(parts.joined(separator: ", "))")
                    lines.append(contentsOf: w.actualDetailLinesForPrompt)
                    if !w.notes_after.isEmpty {
                        lines.append("   Заметки: \(w.notes_after)")
                    }
                }
            }
            if !dayPending.isEmpty {
                lines.append("**Запланированы (ещё не выполнены):**")
                for w in dayPending {
                    var line = "• \(ReportBuilder.sportEmoji(w.sport)) ⬜ \(w.title) — \(w.duration_min) мин, зона \(w.target_zone)"
                    if let rpe = w.rpe_target { line += ", RPE \(rpe)/10" }
                    lines.append(line)
                }
            }
            if dayCompleted.isEmpty && dayPending.isEmpty && !dayRest.isEmpty {
                lines.append("• 😴 День отдыха")
            }

            // Unmatched HK workouts on the day (not represented by a completed planned workout)
            let extraLoggedToday = dayLogged.filter { lw in
                let canon = canonicalSport(lw.sport)
                return !dayCompleted.contains { canonicalSport($0.sport) == canon }
            }
            if !extraLoggedToday.isEmpty {
                lines.append("**Из Apple Health (без плана):**")
                for lw in extraLoggedToday {
                    var parts: [String] = []
                    parts.append("\(Int(lw.durationMin.rounded())) мин")
                    if let hr = lw.avgHR {
                        var s = "ср. ЧСС \(hr)"
                        if let mx = lw.maxHR { s += "/макс \(mx)" }
                        s += " уд/мин"
                        parts.append(s)
                    }
                    if let s = lw.distanceString { parts.append(s) }
                    if let cal = lw.calories { parts.append("\(cal) ккал") }
                    if !lw.startTimeLabel.isEmpty { parts.append(lw.startTimeLabel) }
                    if let src = lw.sourceName { parts.append("источник: \(src)") }
                    lines.append("• \(ReportBuilder.sportEmoji(lw.sport)) 🟦 \(ReportBuilder.sportName(lw.sport)) — \(parts.joined(separator: ", "))")
                }
            }
            lines.append("")
        } else if !dayLogged.isEmpty {
            // No planned workouts at all but there are HK workouts — show them
            lines.append("### Тренировки сегодня (только Apple Health)")
            for lw in dayLogged {
                var parts: [String] = []
                parts.append("\(Int(lw.durationMin.rounded())) мин")
                if let hr = lw.avgHR { parts.append("ср. ЧСС \(hr) уд/мин") }
                if let s = lw.distanceString { parts.append(s) }
                if let cal = lw.calories { parts.append("\(cal) ккал") }
                if !lw.startTimeLabel.isEmpty { parts.append(lw.startTimeLabel) }
                lines.append("• \(ReportBuilder.sportEmoji(lw.sport)) \(ReportBuilder.sportName(lw.sport)) — \(parts.joined(separator: ", "))")
            }
            lines.append("")
        }

        if !weeklyWorkouts.isEmpty || !weeklyLogged.isEmpty {
            let s = weekLoadSummary(weeklyWorkouts, loggedWorkouts: weeklyLogged)
            lines.append("### Тренировочная нагрузка — последние 7 дней")
            if s.plannedCount > 0 {
                lines.append("• Выполнено: \(s.doneCount)/\(s.plannedCount) тренировок (\(Int(s.completionPct))%)")
            } else {
                lines.append("• Тренировок не запланировано")
            }
            if s.actualMin > 0 {
                lines.append("• Объём факт: \(s.actualMin) мин (\(s.actualMin / 60)ч \(s.actualMin % 60)м), план \(s.plannedMin) мин")
            } else if s.plannedMin > 0 {
                lines.append("• Объём план: \(s.plannedMin) мин (\(s.plannedMin / 60)ч \(s.plannedMin % 60)м)")
            }
            if s.restDays > 0 { lines.append("• Дней отдыха: \(s.restDays)") }
            for row in s.bySport {
                lines.append("• \(ReportBuilder.sportEmoji(row.sport)) \(ReportBuilder.sportName(row.sport)): \(row.promptDetail)")
            }
            if let hr = s.avgHR { lines.append("• Средний ЧСС в выполненных: \(hr) уд/мин") }
            if let rpe = s.avgRPE { lines.append("• Средний RPE: \(String(format: "%.1f", rpe))/10") }
            lines.append("")
        }

        if let notes = entry.notes, !notes.isEmpty {
            lines.append("### Заметки атлета")
            lines.append(notes)
            lines.append("")
        }

        lines.append("---")
        lines.append("Проанализируй состояние и готовность к тренировкам.")
        lines.append("")
        lines.append(coaching.adjustmentMode.promptInstruction)
        lines.append("")
        lines.append("Верни **только** JSON-блок:")
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

    // MARK: - Week Load Summary

    struct SportLoad {
        let sport: String
        let count: Int
        let actualMin: Int
        let plannedMin: Int
        let distanceM: Double

        var promptDetail: String {
            var p: [String] = ["\(count) трен."]
            if actualMin > 0 { p.append("\(actualMin) мин") }
            if distanceM > 0 {
                p.append(distanceM >= 1000
                    ? String(format: "%.1f км", distanceM / 1000)
                    : String(format: "%.0f м", distanceM))
            }
            return p.joined(separator: ", ")
        }
    }

    struct WeekLoadSummary {
        let doneCount: Int
        let plannedCount: Int
        let actualMin: Int
        let plannedMin: Int
        let completionPct: Double
        let restDays: Int
        let bySport: [SportLoad]
        let avgHR: Int?
        let avgRPE: Double?
    }

    static func weekLoadSummary(
        _ workouts: [WorkoutPlanJSON],
        loggedWorkouts: [LoggedWorkout] = []
    ) -> WeekLoadSummary {
        let trainable = workouts.filter { $0.sport != "rest" }
        let done = trainable.filter { $0.completed }
        let plannedMin = trainable.reduce(0) { $0 + $1.duration_min }
        var actualMin = done.compactMap { $0.actual_duration_min }.reduce(0, +)
        let pct: Double = trainable.isEmpty ? 0 : Double(done.count) / Double(trainable.count) * 100
        let restCount = workouts.filter { $0.sport == "rest" }.count

        // Dedup logged: skip a HK workout if a planned-completed workout exists on
        // same date with the same canonical sport (its actuals already reflect this HK).
        let extraLogged = loggedWorkouts.filter { lw in
            let canon = canonicalSport(lw.sport)
            return !done.contains { canonicalSport($0.sport) == canon && $0.date == lw.date }
        }
        actualMin += Int(extraLogged.reduce(0.0) { $0 + $1.durationMin }.rounded())

        let order = ["swim", "bike", "bike_indoor", "run", "run_indoor",
                     "strength", "core", "mobility", "stretch",
                     "walk", "hiit", "rowing", "elliptical", "stairs", "other"]

        // Per-sport: combine completed planned + extra logged
        var sportToCount: [String: Int] = [:]
        var sportToActualMin: [String: Int] = [:]
        var sportToPlanMin: [String: Int] = [:]
        var sportToDist: [String: Double] = [:]

        for w in trainable {
            sportToPlanMin[w.sport, default: 0] += w.duration_min
            if w.completed {
                sportToCount[w.sport, default: 0] += 1
                sportToActualMin[w.sport, default: 0] += w.actual_duration_min ?? 0
                sportToDist[w.sport, default: 0] += w.actual_distance_m ?? 0
            }
        }
        for lw in extraLogged {
            sportToCount[lw.sport, default: 0] += 1
            sportToActualMin[lw.sport, default: 0] += Int(lw.durationMin.rounded())
            sportToDist[lw.sport, default: 0] += lw.distanceM ?? 0
        }

        let allSports = Set(sportToCount.keys).union(sportToPlanMin.keys)
        let bySport = allSports
            .sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
            .map { sport -> SportLoad in
                SportLoad(
                    sport: sport,
                    count: sportToCount[sport] ?? 0,
                    actualMin: sportToActualMin[sport] ?? 0,
                    plannedMin: sportToPlanMin[sport] ?? 0,
                    distanceM: sportToDist[sport] ?? 0
                )
            }

        // Average HR: combine planned-completed actual_avg_hr + logged avgHR
        var hrs = done.compactMap { $0.actual_avg_hr }
        hrs += extraLogged.compactMap { $0.avgHR }
        let avgHR = hrs.isEmpty ? nil : hrs.reduce(0, +) / hrs.count

        let rpes = done.compactMap { $0.rpe_actual }
        let avgRPE = rpes.isEmpty ? nil : Double(rpes.reduce(0, +)) / Double(rpes.count)

        let totalDoneCount = done.count + extraLogged.count
        let totalPlanCount = trainable.count

        return WeekLoadSummary(
            doneCount: totalDoneCount, plannedCount: totalPlanCount,
            actualMin: actualMin, plannedMin: plannedMin,
            completionPct: pct, restDays: restCount,
            bySport: bySport, avgHR: avgHR, avgRPE: avgRPE
        )
    }

    /// Map indoor variants to outdoor for cross-source dedup (HK doesn't always distinguish).
    static func canonicalSport(_ s: String) -> String {
        switch s {
        case "run_indoor":  return "run"
        case "bike_indoor": return "bike"
        default:            return s
        }
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

    // MARK: - Local Readiness (computed from HealthKit signals only)

    /// Component contribution to the local readiness score.
    struct ReadinessComponent {
        let label: String
        let delta: Int       // signed contribution to base
        let detail: String   // human-readable explanation
    }

    struct LocalReadiness {
        let score: Int            // clamped 0...100
        let status: String        // отличное/хорошее/удовлетворительное/слабое/плохое
        let components: [ReadinessComponent]
        let warnings: [String]    // red flags from recovery framework
    }

    /// Compute a readiness score from raw HK signals (no AI). Mirrors the
    /// recovery-first framework in `project_tc_recovery_framework.md`.
    /// `history` must include the target entry; we derive baselines from the
    /// preceding days only.
    static func computeLocalReadiness(
        for entry: HealthDayEntry,
        history: [HealthDayEntry],
        profile: AthleteProfile
    ) -> LocalReadiness {
        let base = 75
        var delta = 0
        var components: [ReadinessComponent] = []
        var warnings: [String] = []

        // Sort prior entries (strictly before target date) most-recent first
        let priors = history
            .filter { $0.date < entry.date }
            .sorted { $0.date > $1.date }

        // ── HRV vs 7-day baseline ──────────────────────────────────────────
        let hrv7 = priors.prefix(7).compactMap { $0.hrv.map(Double.init) }
        let hrvBaseline = hrv7.count >= 3
            ? hrv7.reduce(0, +) / Double(hrv7.count)
            : nil
        if let v = entry.hrv.map(Double.init) {
            if let baseline = hrvBaseline {
                let ratio = v / baseline
                if ratio >= 1.10 {
                    components.append(.init(label: "HRV", delta: +8,
                        detail: "\(Int(v)) мс, +\(Int((ratio-1)*100))% к 7-дн (\(Int(baseline)) мс)"))
                    delta += 8
                } else if ratio >= 0.90 {
                    components.append(.init(label: "HRV", delta: 0,
                        detail: "\(Int(v)) мс, в норме (7-дн \(Int(baseline)) мс)"))
                } else if ratio >= 0.80 {
                    components.append(.init(label: "HRV", delta: -10,
                        detail: "\(Int(v)) мс, \(Int((ratio-1)*100))% к 7-дн"))
                    delta -= 10
                } else {
                    components.append(.init(label: "HRV", delta: -25,
                        detail: "\(Int(v)) мс, \(Int((ratio-1)*100))% к 7-дн — red flag"))
                    delta -= 25
                    warnings.append("HRV утром −20%+ от 7-дн среднего → отдых")
                }
            } else {
                components.append(.init(label: "HRV", delta: 0,
                    detail: "\(Int(v)) мс (мало истории для baseline)"))
            }
        }

        // ── RHR vs 60-day baseline ─────────────────────────────────────────
        let rhr60 = priors.prefix(60).compactMap { $0.restingHR.map(Double.init) }
        let rhrBaseline = rhr60.count >= 5
            ? rhr60.reduce(0, +) / Double(rhr60.count)
            : Double(profile.restingHR)
        if let v = entry.restingHR.map(Double.init) {
            let diff = v - rhrBaseline
            if diff <= 1 {
                components.append(.init(label: "Пульс покоя", delta: 0,
                    detail: "\(Int(v)) уд/мин (база \(Int(rhrBaseline)))"))
            } else if diff <= 3 {
                components.append(.init(label: "Пульс покоя", delta: -5,
                    detail: "\(Int(v)) уд/мин, +\(Int(diff)) к базе"))
                delta -= 5
            } else if diff <= 7 {
                components.append(.init(label: "Пульс покоя", delta: -10,
                    detail: "\(Int(v)) уд/мин, +\(Int(diff)) к базе"))
                delta -= 10
            } else {
                components.append(.init(label: "Пульс покоя", delta: -15,
                    detail: "\(Int(v)) уд/мин, +\(Int(diff)) к базе"))
                delta -= 15
            }
        }

        // ── Sleep ──────────────────────────────────────────────────────────
        if let h = entry.sleepHours {
            var d = 0
            var note = "\(String(format: "%.1f", h)) ч"
            if h >= 7.5       { d = 0 }
            else if h >= 6.5  { d = -5 }
            else if h >= 5.5  { d = -10 }
            else              { d = -15 }
            if let deep = entry.sleepDeepHours, deep < 0.5 {
                d -= 5
                note += ", глубокий <30 мин"
                warnings.append("Deep sleep <30 мин → не делать high-intensity")
            }
            components.append(.init(label: "Сон", delta: d, detail: note))
            delta += d
        }
        if let q = entry.sleepQuality {
            if q >= 5      { components.append(.init(label: "Качество сна", delta: +3, detail: "\(q)/5")); delta += 3 }
            else if q <= 2 { components.append(.init(label: "Качество сна", delta: -3, detail: "\(q)/5")); delta -= 3 }
        }

        // ── Wrist temperature ──────────────────────────────────────────────
        if let t = entry.wristTemperatureDelta {
            let abs_t = abs(t)
            if abs_t > 0.5 {
                // Check if elevated 3+ consecutive days
                let priorDeltas = priors.prefix(3).compactMap { $0.wristTemperatureDelta }
                let elevatedRun = priorDeltas.allSatisfy { abs($0) > 0.5 } && priorDeltas.count >= 2
                if elevatedRun {
                    components.append(.init(label: "Темп. запястья", delta: -10,
                        detail: "Δ\(String(format: "%+.2f", t))°C, 3+ дня вне нормы"))
                    delta -= 10
                    warnings.append("Wrist Temp 3+ дня вне typical range → возможна болезнь")
                } else {
                    components.append(.init(label: "Темп. запястья", delta: -5,
                        detail: "Δ\(String(format: "%+.2f", t))°C"))
                    delta -= 5
                }
            }
        }

        // ── Respiratory rate ───────────────────────────────────────────────
        if let rr = entry.respiratoryRate {
            let rr14 = priors.prefix(14).compactMap { $0.respiratoryRate }
            if rr14.count >= 5 {
                let baseline = rr14.reduce(0, +) / Double(rr14.count)
                let diff = rr - baseline
                if diff > 2 {
                    let priorRR = priors.prefix(2).compactMap { $0.respiratoryRate }
                    let elevatedRun = priorRR.count == 2 && priorRR.allSatisfy { $0 - baseline > 2 }
                    if elevatedRun {
                        components.append(.init(label: "Дыхание", delta: -10,
                            detail: "\(String(format: "%.1f", rr)) /мин, 2+ дня выше базы"))
                        delta -= 10
                        warnings.append("Respiratory Rate >baseline 2+ дня → возможна болезнь")
                    } else {
                        components.append(.init(label: "Дыхание", delta: -3,
                            detail: "\(String(format: "%.1f", rr)) /мин, +\(String(format: "%.1f", diff)) к базе"))
                        delta -= 3
                    }
                }
            }
        }

        let score = max(0, min(100, base + delta))
        let status: String
        if score >= 85       { status = "отличное" }
        else if score >= 70  { status = "хорошее" }
        else if score >= 50  { status = "удовлетворительное" }
        else if score >= 35  { status = "слабое" }
        else                 { status = "плохое" }

        return LocalReadiness(score: score, status: status, components: components, warnings: warnings)
    }
}
