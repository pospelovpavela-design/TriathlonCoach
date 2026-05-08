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
