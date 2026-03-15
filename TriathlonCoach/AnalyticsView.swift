import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var healthReader: HealthKitReader

    @State private var weekOffset = 0
    @State private var selectedWorkout: WorkoutPlanJSON?
    @State private var showLogSheet = false
    @State private var isGeneratingReport = false
    @State private var reportCopied = false

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
    }
    private var weekWorkouts: [WorkoutPlanJSON] { store.workouts(forWeek: referenceDate) }
    private var trainable: [WorkoutPlanJSON] { weekWorkouts.filter { $0.sport != "rest" } }
    private var done: Int { trainable.filter { $0.completed }.count }
    private var totalPlanned: Int { trainable.reduce(0) { $0 + $1.duration_min } }
    private var totalActual: Int { weekWorkouts.compactMap { $0.actual_duration_min }.reduce(0, +) }
    private var avgHR: Int? {
        let hrs = weekWorkouts.compactMap { $0.actual_avg_hr }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / hrs.count
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                weekNavigator
                ScrollView {
                    VStack(spacing: 16) {
                        statsRow
                        workoutList
                        if !weekWorkouts.isEmpty {
                            nextWeekButton
                            weekReportButton
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                }
            }
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .sheet(isPresented: $showLogSheet) {
            if let w = selectedWorkout {
                LogWorkoutSheet(workout: w) { updated in
                    store.update(updated)
                    selectedWorkout = nil
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ИТОГИ").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)).tracking(4)
                Text(weekLabel).font(.system(size: 20, weight: .black)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private var weekNavigator: some View {
        HStack {
            Button(action: { weekOffset -= 1 }) {
                Image(systemName: "chevron.left").foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08)).clipShape(Circle())
            }
            Spacer()
            if weekOffset != 0 {
                Button("Эта неделя") { weekOffset = 0 }
                    .font(.system(size: 13)).foregroundColor(.blue)
            }
            Spacer()
            Button(action: { weekOffset += 1 }) {
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08)).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatCard(title: "Выполнено", value: "\(done)/\(trainable.count)", color: .green)
            StatCard(title: "План", value: "\(totalPlanned)м", color: .blue)
            StatCard(title: "Факт", value: totalActual > 0 ? "\(totalActual)м" : "—", color: .orange)
            if let hr = avgHR {
                StatCard(title: "Ср. пульс", value: "\(hr)", color: .red)
            }
        }
    }

    // MARK: - Workout list

    private var workoutList: some View {
        VStack(spacing: 8) {
            if weekWorkouts.isEmpty {
                Text("Нет тренировок на этой неделе")
                    .font(.system(size: 15)).foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ForEach(weekWorkouts) { workout in
                    AnalyticsRow(workout: workout) {
                        selectedWorkout = workout
                        showLogSheet = true
                    }
                }
            }
        }
    }

    // MARK: - Next week button

    private var nextWeekButton: some View {
        Button(action: sendToCoach) {
            HStack {
                Image(systemName: "sparkles")
                Text("Анализ и план на следующую неделю")
                    .fontWeight(.bold)
            }
            .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(LinearGradient(
                colors: [Color(red: 0.5, green: 0.2, blue: 0.9), Color(red: 0.3, green: 0.1, blue: 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Week report button

    private var weekReportButton: some View {
        Button(action: { Task { await generateWeekReport() } }) {
            HStack {
                if isGeneratingReport {
                    ProgressView().tint(.white).scaleEffect(0.8)
                    Text("Читаю Health...").fontWeight(.semibold)
                } else if reportCopied {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Отчёт скопирован!")
                } else {
                    Image(systemName: "doc.on.clipboard")
                    Text("Скопировать отчёт недели для Claude")
                        .fontWeight(.semibold)
                }
            }
            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(reportCopied
                ? Color.green.opacity(0.7)
                : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .disabled(isGeneratingReport)
    }

    private func generateWeekReport() async {
        isGeneratingReport = true
        let (mon, sun) = store.weekBounds(containing: referenceDate)
        let ww = store.workouts(forWeek: referenceDate)

        async let hrv   = healthReader.weeklyHRVValues(from: mon, to: sun)
        async let spo2  = healthReader.weeklySpO2Percent(from: mon, to: sun)
        async let sleep = healthReader.weeklySleepHours(from: mon, to: sun)

        let (hrvVals, spo2Val, sleepVals) = await (hrv, spo2, sleep)

        let report = ReportBuilder.weekReport(
            workouts: ww,
            weekStart: mon,
            weekEnd: sun,
            profile: store.profile,
            weeklyHRV: hrvVals,
            weeklySpO2: spo2Val,
            weeklySleep: sleepVals,
            nextWeekRange: store.nextWeekRange(relativeTo: referenceDate)
        )
        UIPasteboard.general.string = report
        isGeneratingReport = false
        reportCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reportCopied = false }
    }

    // MARK: - Helpers

    private var weekLabel: String {
        let (mon, sun) = store.weekBounds(containing: referenceDate)
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "ru_RU")
        return "\(fmt.string(from: mon)) – \(fmt.string(from: sun))"
    }

    private func sendToCoach() {
        let summary = store.weekSummaryText(forWeek: referenceDate)
        let nextRange = store.nextWeekRange(relativeTo: referenceDate)
        let requestText = "\(summary)\n\nПроанализируй результаты этой недели и составь план тренировок на следующую неделю (\(nextRange))."
        store.pendingPrompt = ClaudeService.buildCopyablePrompt(profile: store.profile, requestText: requestText)
        store.selectedTab = 0
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 17, weight: .black)).foregroundColor(color)
            Text(title).font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity).padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Analytics Row

struct AnalyticsRow: View {
    let workout: WorkoutPlanJSON
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(workout.completed ? Color.green.opacity(0.15) : Color.white.opacity(0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: workout.completed ? "checkmark" : sportIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(workout.completed ? .green : .white.opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title).font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white).lineLimit(1)
                HStack(spacing: 8) {
                    Text(workout.date).font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                    if let actual = workout.actual_duration_min {
                        Text("\(actual) мин").font(.system(size: 12, weight: .medium)).foregroundColor(.orange)
                    } else {
                        Text("\(workout.duration_min) мин план.").font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    if let hr = workout.actual_avg_hr {
                        Text("♥ \(hr)").font(.system(size: 12, weight: .medium)).foregroundColor(.red.opacity(0.8))
                    }
                    if let hrv = workout.hrv_before {
                        Text("HRV \(hrv)").font(.system(size: 12)).foregroundColor(.cyan.opacity(0.7))
                    }
                }
                if !workout.notes_after.isEmpty {
                    Text(workout.notes_after).font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4)).lineLimit(1)
                }
            }
            Spacer()
            Button(action: onLog) {
                Text(workout.completed ? "Изм." : "Лог")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sportIcon: String {
        switch workout.sport {
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
}

// MARK: - Log Workout Sheet

struct LogWorkoutSheet: View {
    @State var workout: WorkoutPlanJSON
    let onSave: (WorkoutPlanJSON) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var healthReader: HealthKitReader

    // Existing fields
    @State private var completed      = false
    @State private var actualDuration = ""
    @State private var actualHR       = ""
    @State private var notes          = ""

    // New fields
    @State private var rpeActual      = ""
    @State private var hrvBefore      = ""
    @State private var hrvAfter       = ""
    @State private var spo2           = ""
    @State private var hrRecovery     = ""
    @State private var restingHR      = ""
    @State private var sleepAvgHR     = ""
    @State private var sleepHours     = ""
    @State private var sleepQuality   = 3
    @State private var hasSleepQuality = false

    @State private var isLoadingHealth = false
    @State private var healthStatus: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Text(workout.title)
                            .font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                        // Completed
                        Toggle(isOn: $completed) {
                            Label("Тренировка выполнена", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.white)
                        }
                        .tint(.green).padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Duration / HR / RPE
                        sectionHeader("Длительность и пульс")
                        HStack(spacing: 12) {
                            inputField("Факт. время (мин)", hint: "\(workout.duration_min)", value: $actualDuration)
                                .keyboardType(.numberPad)
                            inputField("Средний пульс", hint: "уд/мин", value: $actualHR)
                                .keyboardType(.numberPad)
                        }
                        HStack(spacing: 12) {
                            if let rpeT = workout.rpe_target {
                                inputField("RPE факт (план: \(rpeT)/10)", hint: "1–10", value: $rpeActual)
                                    .keyboardType(.numberPad)
                            } else {
                                inputField("RPE факт (1–10)", hint: "1–10", value: $rpeActual)
                                    .keyboardType(.numberPad)
                            }
                            Spacer()
                        }

                        // Recovery — with HealthKit auto-read
                        sectionHeader("Восстановление")
                        healthReadButton
                        if let status = healthStatus {
                            Text(status)
                                .font(.system(size: 12)).foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(spacing: 12) {
                            inputField("HRV до (мс)", hint: "напр. 52", value: $hrvBefore)
                                .keyboardType(.numberPad)
                            inputField("HRV после (мс)", hint: "напр. 44", value: $hrvAfter)
                                .keyboardType(.numberPad)
                        }
                        HStack(spacing: 12) {
                            inputField("SpO2 (%)", hint: "напр. 97", value: $spo2)
                                .keyboardType(.numberPad)
                            inputField("Восст. ЧСС 60с (↓уд/мин)", hint: "напр. 22", value: $hrRecovery)
                                .keyboardType(.numberPad)
                        }
                        HStack(spacing: 12) {
                            inputField("Пульс покоя (утро, уд/мин)", hint: "напр. 52", value: $restingHR)
                                .keyboardType(.numberPad)
                            inputField("Пульс во сне (ср., уд/мин)", hint: "напр. 48", value: $sleepAvgHR)
                                .keyboardType(.numberPad)
                        }

                        // Sleep
                        sectionHeader("Сон накануне")
                        HStack(spacing: 12) {
                            inputField("Часов сна", hint: "напр. 7.5", value: $sleepHours)
                                .keyboardType(.decimalPad)
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Качество сна").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                            HStack(spacing: 6) {
                                ForEach(1...5, id: \.self) { i in
                                    Button(action: {
                                        sleepQuality = i
                                        hasSleepQuality = true
                                    }) {
                                        Text(i <= sleepQuality && hasSleepQuality ? "★" : "☆")
                                            .font(.system(size: 26))
                                            .foregroundColor(i <= sleepQuality && hasSleepQuality ? .yellow : .white.opacity(0.3))
                                    }
                                }
                                if hasSleepQuality {
                                    Text("\(sleepQuality)/5")
                                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                                        .padding(.leading, 4)
                                }
                            }
                        }
                        .padding(14).background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Notes
                        sectionHeader("Заметки")
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Как прошло?", text: $notes, axis: .vertical)
                                .lineLimit(4).foregroundColor(.white)
                                .padding(12).background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Результат").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.foregroundColor(.blue).fontWeight(.semibold)
                }
            }
        }
        .onAppear { loadExisting() }
    }

    // MARK: - Health read button

    private var healthReadButton: some View {
        Button(action: { Task { await readFromHealth() } }) {
            HStack(spacing: 8) {
                if isLoadingHealth {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "heart.text.clipboard")
                }
                Text(isLoadingHealth ? "Читаю Apple Health..." : "Прочитать из Apple Health")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 14)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color(red: 0.9, green: 0.2, blue: 0.3).opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoadingHealth)
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.35)).tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputField(_ label: String, hint: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            TextField(hint, text: value)
                .foregroundColor(.white).padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Logic

    private func loadExisting() {
        completed      = workout.completed
        actualDuration = workout.actual_duration_min.map { "\($0)" } ?? ""
        actualHR       = workout.actual_avg_hr.map { "\($0)" } ?? ""
        notes          = workout.notes_after
        rpeActual      = workout.rpe_actual.map { "\($0)" } ?? ""
        hrvBefore      = workout.hrv_before.map { "\($0)" } ?? ""
        hrvAfter       = workout.hrv_after.map { "\($0)" } ?? ""
        spo2           = workout.spo2_percent.map { "\(Int($0))" } ?? ""
        hrRecovery     = workout.hr_recovery_60s.map { "\($0)" } ?? ""
        restingHR      = workout.resting_hr.map { "\($0)" } ?? ""
        sleepAvgHR     = workout.sleep_avg_hr.map { "\($0)" } ?? ""
        sleepHours     = workout.sleep_hours.map { String(format: "%.1f", $0) } ?? ""
        if let sq = workout.sleep_quality { sleepQuality = sq; hasSleepQuality = true }
    }

    private func readFromHealth() async {
        guard let date = workout.parsedDate else { return }
        isLoadingHealth = true

        async let h   = healthReader.hrv(for: date)
        async let s   = healthReader.spO2Percent(for: date)
        async let sl  = healthReader.sleepResult(nightBefore: date)
        async let rhr = healthReader.restingHR(for: date)
        async let shr = healthReader.sleepHR(nightBefore: date)

        let (hrv, sp, sleepData, resting, sleepHR) = await (h, s, sl, rhr, shr)

        if let v = hrv,       hrvBefore.isEmpty   { hrvBefore   = "\(Int(v))" }
        if let v = sp,        spo2.isEmpty         { spo2        = "\(Int(v))" }
        if let v = sleepData, sleepHours.isEmpty   { sleepHours  = String(format: "%.1f", v.totalHours) }
        if let v = resting,   restingHR.isEmpty    { restingHR   = "\(Int(v))" }
        if let v = sleepHR,   sleepAvgHR.isEmpty   { sleepAvgHR  = "\(Int(v))" }

        isLoadingHealth = false
        let anyFound = hrv != nil || sp != nil || sleepData != nil || resting != nil || sleepHR != nil
        healthStatus = anyFound ? "Данные загружены из Apple Health" : "Данные в Health не найдены за эту дату"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { healthStatus = nil }
    }

    private func save() {
        workout.completed          = completed
        workout.actual_duration_min = Int(actualDuration)
        workout.actual_avg_hr      = Int(actualHR)
        workout.notes_after        = notes
        workout.rpe_actual         = Int(rpeActual)
        workout.hrv_before         = Int(hrvBefore)
        workout.hrv_after          = Int(hrvAfter)
        workout.spo2_percent       = Double(spo2)
        workout.hr_recovery_60s    = Int(hrRecovery)
        workout.resting_hr         = Int(restingHR)
        workout.sleep_avg_hr       = Int(sleepAvgHR)
        workout.sleep_hours        = Double(sleepHours)
        workout.sleep_quality      = hasSleepQuality ? sleepQuality : nil
        onSave(workout)
        dismiss()
    }
}
