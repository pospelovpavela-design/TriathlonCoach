import Foundation

// MARK: - Report builder for Claude feedback prompts

struct ReportBuilder {

    // MARK: - Per-workout report

    static func workoutReport(_ w: WorkoutPlanJSON, profile: AthleteProfile) -> String {
        var L: [String] = []

        L += ["════════════════════════════════════════",
              "ОТЧЁТ О ТРЕНИРОВКЕ",
              "════════════════════════════════════════", ""]

        // Athlete
        L.append("Атлет: \(profile.name)")
        L.append("ЧСС макс: \(profile.maxHR) уд/мин  |  ЧСС покоя: \(profile.restingHR) уд/мин  |  Цель: \(profile.weeklyHoursGoal) ч/нед")
        if !profile.notes.isEmpty { L.append("О себе: \(profile.notes)") }
        L.append("")

        // Workout basics
        L.append("━━━ ТРЕНИРОВКА ━━━")
        L.append("Название: \(w.title)")
        L.append("Вид: \(sportName(w.sport))")
        L.append("Дата: \(w.date)")
        L.append("Статус: \(w.completed ? "✅ Выполнено" : "⬜ Не выполнено")")

        let plannedMin = w.duration_min
        L.append("Длительность план: \(plannedMin) мин")
        if let actual = w.actual_duration_min {
            let diff = actual - plannedMin
            let pct = Int(Double(actual) / Double(plannedMin) * 100)
            let sign = diff >= 0 ? "+" : ""
            L.append("Длительность факт: \(actual) мин (\(sign)\(diff) мин, \(pct)% от плана)")
        }

        let zone = HRZone.zone(for: w.target_zone)
        L.append("Целевая зона: \(w.target_zone)\(zone.map { " — \($0.name), \($0.displayRange)" } ?? "")")

        if let rpeT = w.rpe_target { L.append("RPE план: \(rpeT)/10") }
        if let rpeA = w.rpe_actual {
            let verdict = w.rpe_target.map { rpeA > $0 ? " (тяжелее запланированного)" : rpeA < $0 ? " (легче запланированного)" : " (по плану)" } ?? ""
            L.append("RPE факт: \(rpeA)/10\(verdict)")
        }
        L.append("")

        // HR analysis
        if let hr = w.actual_avg_hr {
            L.append("━━━ АНАЛИЗ ПУЛЬСА ━━━")
            L.append("Средний пульс: \(hr) уд/мин")
            if let z = zone {
                L.append("Целевой диапазон: \(z.displayRange)")
                if hr < z.min {
                    L.append("Оценка: ↓ НИЖЕ зоны на \(z.min - hr) уд/мин")
                } else if hr > z.max && z.max < 220 {
                    L.append("Оценка: ↑ ВЫШЕ зоны на \(hr - z.max) уд/мин")
                } else {
                    L.append("Оценка: ✓ В целевой зоне")
                }
            }
            L.append("")
        }

        // Intervals
        if !w.intervals.isEmpty {
            L.append("━━━ ИНТЕРВАЛЫ ━━━")
            for (i, iv) in w.intervals.enumerated() {
                let z = HRZone.zone(for: iv.zone)
                L.append("\(i + 1). \(iv.note)  |  \(iv.duration_min) мин  |  \(iv.zone) \(z?.displayRange ?? "")")
            }
            L.append("Итого по интервалам: \(w.intervals.reduce(0) { $0 + $1.duration_min }) мин")
            L.append("")
        }

        // Recovery metrics
        let hasRecovery = w.hrv_before != nil || w.hrv_after != nil
            || w.spo2_percent != nil || w.hr_recovery_60s != nil
            || w.resting_hr != nil || w.sleep_avg_hr != nil
        if hasRecovery {
            L.append("━━━ ВОССТАНОВЛЕНИЕ ━━━")
            if let rhr = w.resting_hr {
                L.append("Пульс покоя (утро): \(rhr) уд/мин  \(restingHRQuality(rhr))")
            }
            if let shr = w.sleep_avg_hr {
                L.append("Пульс во сне (ср.): \(shr) уд/мин")
            }
            if let hb = w.hrv_before {
                L.append("HRV до тренировки: \(hb) мс  \(hrvQuality(hb))")
            }
            if let ha = w.hrv_after {
                L.append("HRV после тренировки: \(ha) мс  \(hrvQuality(ha))")
            }
            if let hb = w.hrv_before, let ha = w.hrv_after {
                let diff = ha - hb
                let sign = diff >= 0 ? "+" : ""
                let pct = hb > 0 ? "  (\(sign)\(Int(Double(diff) / Double(hb) * 100))%)" : ""
                L.append("Изменение HRV: \(sign)\(diff) мс\(pct)")
            }
            if let rec = w.hr_recovery_60s {
                L.append("Восстановление ЧСС (60 сек): -\(rec) уд/мин  \(hrRecoveryQuality(rec))")
            }
            if let spo2 = w.spo2_percent {
                L.append("SpO2: \(Int(spo2))%  \(spO2Quality(spo2))")
            }
            L.append("")
        }

        // Sleep
        if let sh = w.sleep_hours {
            L.append("━━━ СОН НАКАНУНЕ ━━━")
            L.append("Продолжительность: \(String(format: "%.1f", sh)) ч  \(sleepLabel(sh))")
            if let sq = w.sleep_quality {
                let stars = String(repeating: "★", count: sq) + String(repeating: "☆", count: 5 - sq)
                L.append("Качество (субъективно): \(sq)/5  \(stars)")
            }
            L.append("")
        }

        // Notes
        if !w.notes_after.isEmpty {
            L.append("━━━ ЗАМЕТКИ ПОСЛЕ ━━━")
            L.append(w.notes_after)
            L.append("")
        }

        if !w.tags.isEmpty {
            L.append("Теги: \(w.tags.joined(separator: ", "))")
            L.append("")
        }

        // Claude prompt
        L += ["════════════════════════════════════════",
              "ЗАПРОС К ТРЕНЕРУ-ИИ:", ""]
        L.append("Ты — профессиональный тренер по триатлону. Проанализируй тренировку атлета \(profile.name).")
        L.append("")
        L += zoneReference()
        L.append("")
        L += ["Ответь развёрнуто:",
              "1. Как выполнена тренировка относительно плана — пульс, длительность, RPE?",
              "2. Что говорят данные восстановления (HRV, ЧСС восстановление, SpO2, сон) о текущем состоянии?",
              "3. Требуется ли коррекция ближайших тренировок?",
              "4. Дай 2–3 конкретных рекомендации на следующие 24–48 часов."]

        return L.joined(separator: "\n")
    }

    // MARK: - Weekly report

    static func weekReport(
        workouts: [WorkoutPlanJSON],
        weekStart: Date,
        weekEnd: Date,
        profile: AthleteProfile,
        weeklyHRV: [Double],
        weeklySpO2: Double?,
        weeklySleep: [Double],
        nextWeekRange: String
    ) -> String {
        var L: [String] = []

        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "ru_RU")
        let weekLabel = "\(fmt.string(from: weekStart)) – \(fmt.string(from: weekEnd))"

        L += ["════════════════════════════════════════",
              "ИТОГИ ТРЕНИРОВОЧНОЙ НЕДЕЛИ: \(weekLabel)",
              "════════════════════════════════════════", ""]

        // Athlete
        L.append("Атлет: \(profile.name)")
        L.append("ЧСС макс: \(profile.maxHR)  |  ЧСС покоя: \(profile.restingHR)  |  Цель: \(profile.weeklyHoursGoal) ч/нед")
        if !profile.notes.isEmpty { L.append("О себе: \(profile.notes)") }
        L.append("")

        // Volume
        let trainable = workouts.filter { $0.sport != "rest" }
        let done = trainable.filter { $0.completed }
        let totalPlanned = trainable.reduce(0) { $0 + $1.duration_min }
        let totalActual  = done.compactMap { $0.actual_duration_min }.reduce(0, +)
        let pct = trainable.isEmpty ? 0 : Int(Double(done.count) / Double(trainable.count) * 100)

        L.append("━━━ ОБЪЁМ НЕДЕЛИ ━━━")
        L.append("Тренировок: \(done.count)/\(trainable.count) (\(pct)% выполнения)")
        L.append("Запланировано: \(totalPlanned) мин (\(totalPlanned / 60)ч \(totalPlanned % 60)м)")
        if totalActual > 0 {
            L.append("Выполнено: \(totalActual) мин (\(totalActual / 60)ч \(totalActual % 60)м)")
        }
        let restDays = workouts.filter { $0.sport == "rest" }.count
        if restDays > 0 { L.append("Дней отдыха: \(restDays)") }
        L.append("")

        // Sport breakdown
        let byType = Dictionary(grouping: trainable, by: { $0.sport })
        if !byType.isEmpty {
            L.append("━━━ ПО ВИДАМ СПОРТА ━━━")
            let order = ["swim","bike","run","bike_indoor","run_indoor","strength","core","mobility","stretch"]
            for sport in byType.keys.sorted(by: { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }) {
                let ws = byType[sport] ?? []
                let p = ws.reduce(0) { $0 + $1.duration_min }
                let a = ws.compactMap { $0.actual_duration_min }.reduce(0, +)
                let d = ws.filter { $0.completed }.count
                var line = "\(sportEmoji(sport)) \(sportName(sport)): план \(p) мин, \(d)/\(ws.count) тренировок"
                if a > 0 { line += ", факт \(a) мин" }
                L.append(line)
            }
            L.append("")
        }

        // Day-by-day
        L.append("━━━ ТРЕНИРОВКИ ПО ДНЯМ ━━━")
        let cal = Calendar.current
        let isoFmt = DateFormatter(); isoFmt.dateFormat = "yyyy-MM-dd"
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "EEE, d MMM"; dayFmt.locale = Locale(identifier: "ru_RU")
        var day = weekStart
        while day <= weekEnd {
            let key = isoFmt.string(from: day)
            let dayW = workouts.filter { $0.date == key }
            let label = dayFmt.string(from: day).capitalized
            if dayW.isEmpty {
                L.append("\(label) — отдых")
            } else {
                for w in dayW {
                    L.append("")
                    L.append("\(label)  [\(sportEmoji(w.sport)) \(sportName(w.sport).uppercased())]  \(w.completed ? "✅" : "⬜")")
                    L.append("  Название: \(w.title)")
                    var dur = "  Длит.: план \(w.duration_min) мин"
                    if let a = w.actual_duration_min { dur += " / факт \(a) мин" }
                    L.append(dur)
                    var hr = "  Пульс: цель \(w.target_zone)"
                    if let h = w.actual_avg_hr { hr += " / ср. факт \(h) уд/мин" }
                    L.append(hr)
                    if let rpeT = w.rpe_target, let rpeA = w.rpe_actual {
                        L.append("  RPE: план \(rpeT)/10 / факт \(rpeA)/10")
                    } else if let rpe = w.rpe_target {
                        L.append("  RPE план: \(rpe)/10")
                    }
                    if let rhr = w.resting_hr  { L.append("  Пульс покоя: \(rhr) уд/мин") }
                    if let shr = w.sleep_avg_hr { L.append("  Пульс во сне: \(shr) уд/мин") }
                    if w.hrv_before != nil || w.hrv_after != nil {
                        var h = "  HRV:"
                        if let hb = w.hrv_before { h += " до \(hb) мс" }
                        if let ha = w.hrv_after  { h += " / после \(ha) мс" }
                        L.append(h)
                    }
                    if let rec = w.hr_recovery_60s { L.append("  Восст. ЧСС 60с: -\(rec) уд/мин") }
                    if let spo2 = w.spo2_percent   { L.append("  SpO2: \(Int(spo2))%") }
                    if let sh = w.sleep_hours {
                        var sl = "  Сон накануне: \(String(format: "%.1f", sh)) ч"
                        if let sq = w.sleep_quality { sl += " (качество \(sq)/5)" }
                        L.append(sl)
                    }
                    if !w.notes_after.isEmpty { L.append("  Заметки: \(w.notes_after)") }
                    if !w.intervals.isEmpty {
                        let desc = w.intervals.map { "\($0.note) \($0.duration_min)м[\($0.zone)]" }.joined(separator: " → ")
                        L.append("  Интервалы: \(desc)")
                    }
                }
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        L.append("")

        // Weekly recovery summary
        if !weeklyHRV.isEmpty || weeklySpO2 != nil || !weeklySleep.isEmpty {
            L.append("━━━ ДАННЫЕ ВОССТАНОВЛЕНИЯ ЗА НЕДЕЛЮ ━━━")

            if !weeklyHRV.isEmpty {
                let avg = weeklyHRV.reduce(0, +) / Double(weeklyHRV.count)
                let minV = weeklyHRV.min() ?? 0
                let maxV = weeklyHRV.max() ?? 0
                L.append("HRV (мс): мин \(Int(minV)) / макс \(Int(maxV)) / среднее \(Int(avg))  \(hrvQuality(Int(avg)))")
                if weeklyHRV.count >= 4 {
                    let mid = weeklyHRV.count / 2
                    let first = weeklyHRV.prefix(mid).reduce(0, +) / Double(mid)
                    let last  = weeklyHRV.suffix(mid).reduce(0, +) / Double(mid)
                    let trend = last > first + 2 ? "📈 растёт (улучшение)" : last < first - 2 ? "📉 падает (накопление усталости)" : "➡️ стабильный"
                    L.append("Тренд HRV: \(trend)")
                }
            }

            if let spo2 = weeklySpO2 {
                L.append("SpO2 среднее: \(spo2)%  \(spO2Quality(spo2))")
            }

            if !weeklySleep.isEmpty {
                let avg = weeklySleep.reduce(0, +) / Double(weeklySleep.count)
                let minS = weeklySleep.min() ?? 0
                let maxS = weeklySleep.max() ?? 0
                L.append("Сон (ч): мин \(String(format: "%.1f", minS)) / макс \(String(format: "%.1f", maxS)) / среднее \(String(format: "%.1f", avg))  \(sleepLabel(avg))")
            }

            let hrs = trainable.compactMap { $0.actual_avg_hr }
            if !hrs.isEmpty {
                L.append("Средний ЧСС по тренировкам: \(hrs.reduce(0, +) / hrs.count) уд/мин")
            }
            let restingHRs = workouts.compactMap { $0.resting_hr }
            if !restingHRs.isEmpty {
                let avg = restingHRs.reduce(0, +) / restingHRs.count
                let minV = restingHRs.min() ?? 0
                let maxV = restingHRs.max() ?? 0
                L.append("Пульс покоя (ср.): \(avg) уд/мин (мин \(minV) / макс \(maxV))  \(restingHRQuality(avg))")
            }
            let sleepHRs = workouts.compactMap { $0.sleep_avg_hr }
            if !sleepHRs.isEmpty {
                let avg = sleepHRs.reduce(0, +) / sleepHRs.count
                L.append("Пульс во сне (ср.): \(avg) уд/мин (мин \(sleepHRs.min() ?? 0) / макс \(sleepHRs.max() ?? 0))")
            }
            L.append("")
        }

        // Claude prompt
        L += ["════════════════════════════════════════",
              "ЗАПРОС К ТРЕНЕРУ-ИИ:", ""]
        L.append("Ты — профессиональный тренер по триатлону. Перед тобой итоги тренировочной недели атлета \(profile.name).")
        L.append("")
        L += zoneReference()
        L.append("Виды спорта (только эти значения в поле \"sport\"): run, bike, swim, strength, mobility, rest, bike_indoor, run_indoor, core, stretch")
        L.append("")
        L += ["Проанализируй неделю и ответь:",
              "1. Общая оценка: выполнение плана, распределение нагрузки по видам спорта и зонам.",
              "2. Анализ восстановления (HRV, SpO2, сон): в норме ли атлет, есть ли признаки перегрузки?",
              "3. Что прошло хорошо, что вызывает вопросы?",
              "4. Составь детальный план на следующую неделю (\(nextWeekRange)) с учётом текущего состояния.", ""]
        L += ["Включи JSON-план строго в формате:",
              "```json",
              "[",
              "  {",
              "    \"title\": \"Название\", \"sport\": \"run\", \"date\": \"yyyy-MM-dd\",",
              "    \"duration_min\": 45, \"target_zone\": \"Z2\", \"description\": \"...\",",
              "    \"intervals\": [{\"duration_min\": 10, \"zone\": \"Z1\", \"note\": \"Разминка\"}],",
              "    \"tags\": [\"run\",\"z2\"], \"rpe_target\": 6,",
              "    \"planned\": true, \"completed\": false,",
              "    \"actual_avg_hr\": null, \"actual_duration_min\": null, \"notes_after\": \"\"",
              "  }",
              "]",
              "```"]

        return L.joined(separator: "\n")
    }

    // MARK: - Shared helpers

    static func sportName(_ sport: String) -> String {
        switch sport {
        case "run":         return "Бег"
        case "bike":        return "Велосипед"
        case "swim":        return "Плавание"
        case "strength":    return "Силовая"
        case "mobility":    return "Подвижность"
        case "bike_indoor": return "Велотренажёр"
        case "run_indoor":  return "Беговая дорожка"
        case "core":        return "Кор"
        case "stretch":     return "Растяжка"
        case "rest":        return "Отдых"
        default:            return sport
        }
    }

    static func sportEmoji(_ sport: String) -> String {
        switch sport {
        case "run", "run_indoor": return "🏃"
        case "bike", "bike_indoor": return "🚴"
        case "swim":        return "🏊"
        case "strength":    return "🏋️"
        case "core":        return "💪"
        case "mobility", "stretch": return "🧘"
        case "rest":        return "😴"
        default:            return "•"
        }
    }

    static func hrvQuality(_ ms: Int) -> String {
        switch ms {
        case 70...:   return "(отлично)"
        case 50..<70: return "(хорошо)"
        case 35..<50: return "(норма)"
        case 20..<35: return "(низкий — возможна усталость)"
        default:      return "(очень низкий — нужно восстановление)"
        }
    }

    static func restingHRQuality(_ bpm: Int) -> String {
        switch bpm {
        case ..<50: return "(отлично — высокая аэробная форма)"
        case 50..<60: return "(хорошо)"
        case 60..<70: return "(норма)"
        case 70..<80: return "(умеренно повышен)"
        default:      return "(повышен — возможна усталость или стресс)"
        }
    }

    static func hrRecoveryQuality(_ drop: Int) -> String {
        switch drop {
        case 25...:   return "(отлично)"
        case 20..<25: return "(хорошо)"
        case 12..<20: return "(норма)"
        default:      return "(низкое — возможна усталость)"
        }
    }

    static func spO2Quality(_ pct: Double) -> String {
        switch pct {
        case 97...:   return "(норма)"
        case 95..<97: return "(норма)"
        case 92..<95: return "(пониженный)"
        default:      return "(низкий)"
        }
    }

    static func sleepLabel(_ hours: Double) -> String {
        switch hours {
        case 8...:  return "(отлично)"
        case 7..<8: return "(хорошо)"
        case 6..<7: return "(достаточно)"
        default:    return "(недостаточно)"
        }
    }

    private static func zoneReference() -> [String] {
        ["Пульсовые зоны атлета:",
         "• Z1: до 119 уд/мин — восстановление",
         "• Z2: 120–145 уд/мин — аэробная база",
         "• Z3: 146–163 уд/мин — аэробный порог",
         "• Z4: 164–175 уд/мин — анаэробный порог",
         "• Z5: 176+ уд/мин — максимум"]
    }
}
