import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject var store: AppStore

    @State private var weekOffset = 0
    @State private var selectedWorkout: WorkoutPlanJSON?
    @State private var showLogSheet = false

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
            Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                weekNavigator
                ScrollView {
                    VStack(spacing: 16) {
                        statsRow
                        workoutList
                        if !weekWorkouts.isEmpty {
                            nextWeekButton
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                }
            }
        }
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
        .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 8)
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

    private var weekLabel: String {
        let (mon, sun) = store.weekBounds(containing: referenceDate)
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "ru_RU")
        return "\(fmt.string(from: mon)) – \(fmt.string(from: sun))"
    }

    private func sendToCoach() {
        let summary = store.weekSummaryText(forWeek: referenceDate)
        let nextRange = store.nextWeekRange()
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
        case "run": return "figure.run"
        case "bike": return "figure.outdoor.cycle"
        case "swim": return "figure.pool.swim"
        case "strength": return "dumbbell"
        case "rest": return "moon.zzz"
        default: return "heart"
        }
    }
}

// MARK: - Log Workout Sheet

struct LogWorkoutSheet: View {
    @State var workout: WorkoutPlanJSON
    let onSave: (WorkoutPlanJSON) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var completed: Bool = false
    @State private var actualDuration: String = ""
    @State private var actualHR: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        Text(workout.title)
                            .font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                        Toggle(isOn: $completed) {
                            Label("Тренировка выполнена", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.white)
                        }
                        .tint(.green).padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        inputField("Фактическое время (мин)", hint: "\(workout.duration_min)", value: $actualDuration)
                            .keyboardType(.numberPad)
                        inputField("Средний пульс (уд/мин)", hint: "Например: 142", value: $actualHR)
                            .keyboardType(.numberPad)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Заметки").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
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
        .onAppear {
            completed = workout.completed
            actualDuration = workout.actual_duration_min.map { "\($0)" } ?? ""
            actualHR = workout.actual_avg_hr.map { "\($0)" } ?? ""
            notes = workout.notes_after
        }
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

    private func save() {
        workout.completed = completed
        workout.actual_duration_min = Int(actualDuration)
        workout.actual_avg_hr = Int(actualHR)
        workout.notes_after = notes
        onSave(workout)
        dismiss()
    }
}
