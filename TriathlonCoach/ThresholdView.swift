import SwiftUI

struct ThresholdView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var wkManager: WorkoutKitManager
    @EnvironmentObject var healthReader: HealthKitReader

    @State private var testDate = Date()
    @State private var sport = "run"
    @State private var testWorkout: WorkoutPlanJSON?
    @State private var thresholdHR: Int?
    @State private var status: String?
    @State private var copied = false
    @State private var isLoadingHealth = false

    private let sports = [
        ("run", "Бег"),
        ("bike", "Вело"),
        ("run_indoor", "Бег indoor"),
        ("bike_indoor", "Вело indoor")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                testBuilderSection
                protocolSection
                workoutSection
                resultSection
                coachSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .onAppear(perform: loadExistingTest)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ПАНО")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(4)
                Text("Порог и зоны")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var testBuilderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Тест")

            VStack(spacing: 12) {
                DatePicker("Дата", selection: $testDate, displayedComponents: .date)
                    .foregroundColor(.white)
                    .tint(.blue)

                Picker("Вид", selection: $sport) {
                    ForEach(sports, id: \.0) { item in
                        Text(item.1).tag(item.0)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: createOrUpdateTest) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Сформировать тест ПАНО")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Как выполнять")

            VStack(spacing: 10) {
                instructionRow(
                    icon: "checkmark.shield",
                    title: "Перед стартом",
                    text: "Тест выполняй только если здоров: без температуры, недомогания, острой боли, сильного недосыпа и остаточной тяжести после тяжелой тренировки.",
                    color: .green
                )
                instructionRow(
                    icon: "figure.run",
                    title: "Разминка",
                    text: "15 минут очень легко, затем 5 минут плавно ускорься до устойчиво тяжелого ритма. Не закисляйся до тестового блока.",
                    color: .blue
                )
                instructionRow(
                    icon: "speedometer",
                    title: "Тест 30 минут",
                    text: "Первые 10 минут держи себя в руках без рывка. Последние 20 минут беги или крути максимально ровно: тяжело, но устойчиво, RPE 8-9.",
                    color: .orange
                )
                instructionRow(
                    icon: "heart.text.square",
                    title: "Контроль каждые 5 минут",
                    text: "Проверь дыхание, технику, координацию и способность удерживать темп. Если форма разваливается или пульс ведет себя необычно, снизь интенсивность.",
                    color: .pink
                )
                instructionRow(
                    icon: "exclamationmark.triangle",
                    title: "Когда остановиться",
                    text: "Прекрати тест при боли в груди, головокружении, тошноте, резкой нехватке воздуха, потере координации, острой боли или необычно высоком/скачущем пульсе.",
                    color: .red
                )
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("WorkoutKit / Apple Fitness")

            if let workout = testWorkout {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: workout.sportIcon)
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text("\(workout.date) · \(workout.duration_min) мин · \(workout.intervals.count) отрезков")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(workout.intervals) { interval in
                            HStack(spacing: 8) {
                                Text(interval.zone)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(zoneSwiftUIColor(interval.zone))
                                    .frame(width: 34, alignment: .leading)
                                Text("\(interval.duration_min) мин")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.55))
                                    .frame(width: 52, alignment: .leading)
                                Text(interval.note)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button(action: sendToWatch) {
                            buttonLabel("applewatch", wkManager.isAlreadySaved(workout.title) ? "На Watch" : "В Fitness")
                        }
                        .disabled(wkManager.authorizationStatus != .authorized || wkManager.isLoading)

                        Button(action: { Task { await readResultFromHealth() } }) {
                            buttonLabel("heart.text.square", isLoadingHealth ? "Читаю..." : "Загрузить факт")
                        }
                        .disabled(isLoadingHealth)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                emptyState("Сначала сформируй тестовую тренировку.")
            }

            if let status {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Результат и зоны")

            let activeThreshold = thresholdHR ?? store.profile.lactateThresholdHR
            if let lthr = activeThreshold {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(lthr)")
                            .font(.system(size: 46, weight: .black))
                            .foregroundColor(.white)
                        Text("уд/мин")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }

                    VStack(spacing: 8) {
                        ForEach(store.profile.thresholdZones(for: lthr), id: \.key) { zone in
                            HStack(spacing: 12) {
                                Text(zone.key)
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundColor(zoneSwiftUIColor(String(zone.key.prefix(2))))
                                    .frame(width: 36, alignment: .leading)
                                Text(zone.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                                Text("\(zone.range) уд/мин")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    Button(action: saveThresholdToProfile) {
                        HStack {
                            Image(systemName: "heart.circle.fill")
                            Text("Интегрировать в профиль и Health-промты")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                emptyState("После загрузки факта ПАНО будет рассчитано по среднему пульсу последних 20 минут тестового блока.")
            }
        }
    }

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Комментарий тренера")

            Button(action: copyCoachPrompt) {
                HStack {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Промт скопирован" : "Получить комментарий тренера")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(testWorkout == nil)

            Text("Скопирует отчёт по тесту ПАНО для Claude: выполнение, достоверность результата, зоны и рекомендации по плану.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .tracking(3)
    }

    private func buttonLabel(_ icon: String, _ text: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func instructionRow(icon: String, title: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func createOrUpdateTest() {
        let workout = makeThresholdWorkout()
        testWorkout = workout
        store.addOrReplace([workout])
        status = "Тест добавлен в план. Отправь его в Fitness и выполни на Apple Watch."
    }

    private func sendToWatch() {
        guard let workout = testWorkout else { return }
        Task {
            let success = await wkManager.saveWorkout(workout)
            status = success
                ? "Тренировка отправлена в Fitness/Apple Watch."
                : (wkManager.lastError ?? "Не удалось отправить тренировку.")
        }
    }

    private func readResultFromHealth() async {
        guard var workout = testWorkout, let date = workout.parsedDate else { return }
        isLoadingHealth = true
        defer { isLoadingHealth = false }

        let candidates = await healthReader.allWorkoutData(sport: workout.sport, on: date)
        guard let result = candidates.max(by: { $0.durationMin < $1.durationMin }) else {
            status = "В Apple Health не найдена тренировка для этого теста."
            return
        }

        workout.completed = true
        workout.actual_duration_min = Int(result.durationMin.rounded())
        workout.actual_avg_hr = result.avgHR
        workout.actual_max_hr = result.maxHR
        workout.actual_distance_m = result.distanceM
        workout.actual_calories = result.calories
        workout.actual_intervals = result.intervals.map {
            ActualInterval(
                number: $0.number,
                duration_min: $0.durationMin,
                avg_hr: $0.avgHR,
                max_hr: $0.maxHR,
                distance_m: $0.distanceM
            )
        }

        let lthr = estimateThresholdHR(from: workout)
        if let lthr {
            thresholdHR = lthr
            workout.notes_after = "ПАНО/LTHR рассчитан по тесту: \(lthr) уд/мин."
            status = "Факт загружен. ПАНО рассчитан: \(lthr) уд/мин."
        } else {
            status = "Факт загружен, но недостаточно данных ЧСС для расчёта ПАНО."
        }

        testWorkout = workout
        store.update(workout)
    }

    private func saveThresholdToProfile() {
        guard let lthr = thresholdHR ?? store.profile.lactateThresholdHR else { return }
        var profile = store.profile
        profile.lactateThresholdHR = lthr
        profile.lactateThresholdSport = sport
        profile.lactateThresholdTestDate = isoKey(testDate)
        store.saveProfile(profile)
        status = "ПАНО и зоны сохранены в профиль. Теперь они попадут в промпты тренера и Health."
    }

    private func copyCoachPrompt() {
        guard let workout = testWorkout else { return }
        var prompt = ReportBuilder.workoutReport(workout, profile: store.profile)
        if let lthr = thresholdHR ?? store.profile.lactateThresholdHR {
            prompt += "\n\nПАНО/LTHR по тесту: \(lthr) уд/мин.\n"
            prompt += "Зоны от ПАНО: \(store.profile.thresholdZoneSummary(for: lthr)).\n"
            prompt += "Оцени достоверность теста, корректность зон и как адаптировать целевой план."
        }
        prompt += "\n\nПротокол теста:\n\(thresholdProtocolText)"
        UIPasteboard.general.string = prompt
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }

    private func loadExistingTest() {
        let key = isoKey(testDate)
        if let existing = store.workouts.first(where: { $0.date == key && $0.tags.contains("pano-test") }) {
            testWorkout = existing
            thresholdHR = estimateThresholdHR(from: existing) ?? store.profile.lactateThresholdHR
        } else {
            thresholdHR = store.profile.lactateThresholdHR
        }
    }

    private func makeThresholdWorkout() -> WorkoutPlanJSON {
        WorkoutPlanJSON(
            title: "ПАНО тест",
            sport: sport,
            date: isoKey(testDate),
            duration_min: 60,
            target_zone: "Z4",
            description: thresholdProtocolText,
            intervals: [
                IntervalJSON(duration_min: 15, zone: "Z1", note: "Разминка: легко, проверь самочувствие"),
                IntervalJSON(duration_min: 5, zone: "Z2", note: "Плавно ускорься, без закисления"),
                IntervalJSON(duration_min: 10, zone: "Z4", note: "Тест: ровно, без стартового рывка"),
                IntervalJSON(duration_min: 20, zone: "Z4", note: "ПАНО: максимум ровно, RPE 8-9"),
                IntervalJSON(duration_min: 10, zone: "Z1", note: "Заминка: легко, восстанови дыхание")
            ],
            tags: ["pano-test", "threshold", sport],
            rpe_target: 9,
            planned: true,
            completed: false,
            actual_avg_hr: nil,
            actual_duration_min: nil,
            notes_after: ""
        )
    }

    private var thresholdProtocolText: String {
        """
        Полевой тест ПАНО/LTHR на 60 минут. Выполняй только при нормальном самочувствии: без температуры, недомогания, боли в груди, острой боли, сильного недосыпа и тяжелой остаточной усталости. Разминка 15 минут Z1 очень легко, затем 5 минут плавный выход к устойчиво тяжелому ритму без закисления. Основной тест 30 минут: первые 10 минут контролируемо, без рывка; последние 20 минут максимально ровно на усилии RPE 8-9, тяжело, но устойчиво. Каждые 5 минут контролируй дыхание, технику, координацию, способность держать темп и поведение пульса. Снизь интенсивность или остановись при боли в груди, головокружении, тошноте, резкой нехватке воздуха, потере координации, острой боли или необычно высоком/скачущем пульсе. Заминка 10 минут Z1, не останавливайся резко. ПАНО считается по средней ЧСС последних 20 минут тестового блока.
        """
    }

    private func estimateThresholdHR(from workout: WorkoutPlanJSON) -> Int? {
        if let testBlock = workout.actual_intervals?.first(where: { $0.number == 4 }),
           let hr = testBlock.avg_hr {
            return hr
        }
        if let intervals = workout.actual_intervals, intervals.count >= 2 {
            let lastHard = intervals.filter { $0.number >= 3 && $0.number <= 4 }.compactMap { item -> (hr: Int, minutes: Double)? in
                guard let hr = item.avg_hr else { return nil }
                return (hr, item.duration_min)
            }
            let totalMinutes = lastHard.reduce(0.0) { $0 + $1.minutes }
            if totalMinutes > 0 {
                let weighted = lastHard.reduce(0.0) { $0 + Double($1.hr) * $1.minutes } / totalMinutes
                return Int(weighted.rounded())
            }
        }
        return workout.actual_avg_hr
    }

    private func isoKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
