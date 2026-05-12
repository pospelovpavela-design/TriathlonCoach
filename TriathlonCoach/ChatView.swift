import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var healthReader: HealthKitReader

    @State private var promptOverride: String? = nil   // set by external pendingPrompt
    @State private var pastedResponse: String = ""
    @State private var extractedWorkouts: [WorkoutPlanJSON] = []
    @State private var extractedDeletes: [ClaudeService.DeleteRequest] = []
    @State private var loadedCount: Int? = nil
    @State private var deletedCount: Int? = nil
    @State private var copied = false
    @State private var selectedRequest: PlanRequest = .today
    @State private var todayPreferences: String = ""
    @FocusState private var prefsFocused: Bool
    @FocusState private var pasteFocused: Bool

    private var generatedPrompt: String {
        promptOverride ?? autoPrompt
    }

    enum PlanRequest: String, CaseIterable {
        case today    = "Сегодня"
        case thisWeek = "Эта неделя"
        case nextWeek = "Следующая"
        case recovery = "Восстановление"
        case preRace  = "Пред-старт"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                step1Section
                step2Section
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    prefsFocused = false
                    pasteFocused = false
                }
                .fontWeight(.semibold)
            }
        }
        .task {
            await store.refreshLoggedWorkouts(daysBack: 13, healthReader: healthReader)
        }
        .onChange(of: store.pendingPrompt) { msg in
            guard !msg.isEmpty else { return }
            promptOverride = msg
            pastedResponse = ""
            extractedWorkouts = []
            extractedDeletes = []
            loadedCount  = nil
            deletedCount = nil
            store.pendingPrompt = ""
        }
        .onChange(of: selectedRequest) { _ in
            promptOverride = nil
            pastedResponse = ""
            extractedWorkouts = []
            extractedDeletes = []
            loadedCount  = nil
            deletedCount = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ТРЕНЕР").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)).tracking(4)
                Text("Промт-помощник").font(.system(size: 24, weight: .black)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.top, 16).padding(.bottom, 4)
    }

    // MARK: - Step 1

    private var step1Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel("1", "Выбери запрос и скопируй промт")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlanRequest.allCases, id: \.self) { req in
                        Button(req.rawValue) { selectedRequest = req }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedRequest == req ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedRequest == req ? Color.blue : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 1)
            }

            preferencesField

            Text(generatedPrompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))

            Button(action: copyPrompt) {
                HStack {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Скопировано!" : "Скопировать промт")
                }
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(copied ? Color.green.opacity(0.85) : Color.blue.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.circle").foregroundColor(.white.opacity(0.3))
                Text("Открой claude.ai, вставь промт, получи ответ")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
            }
        }
    }

    // MARK: - Step 2

    private var step2Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel("2", "Вставь ответ от Claude")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedResponse)
                    .focused($pasteFocused)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 130, maxHeight: 260)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
                    .onChange(of: pastedResponse, perform: parseResponse)

                if pastedResponse.isEmpty {
                    Text("Вставь ответ Claude с JSON-планом...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.22))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            if !extractedWorkouts.isEmpty || !extractedDeletes.isEmpty {
                loadBanner
            }
        }
    }

    private var foundSummary: String {
        var p: [String] = []
        if !extractedWorkouts.isEmpty { p.append("\(extractedWorkouts.count) трен.") }
        if !extractedDeletes.isEmpty  { p.append("\(extractedDeletes.count) к удалению") }
        return p.joined(separator: ", ")
    }

    private var doneSummary: String? {
        guard loadedCount != nil || deletedCount != nil else { return nil }
        var p: [String] = []
        if let n = loadedCount  { p.append("загружено \(n)") }
        if let n = deletedCount, n > 0 { p.append("удалено \(n)") }
        return p.isEmpty ? nil : p.joined(separator: ", ")
    }

    private var loadBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 20)).foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Найдено: \(foundSummary)")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                if let d = doneSummary {
                    Text("✓ \(d)")
                        .font(.system(size: 12)).foregroundColor(.green)
                } else {
                    Text("Нажми чтобы применить к плану")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            if loadedCount == nil && deletedCount == nil {
                Button(action: loadPlan) {
                    Text("Применить")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.green).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Preferences input

    private var preferencesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Пожелания / возможности на сегодня")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55)).tracking(1)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $todayPreferences)
                    .focused($prefsFocused)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(minHeight: 60, maxHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
                if todayPreferences.isEmpty {
                    Text("Время, локация, оборудование, что хочется/не хочется...")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.22))
                        .padding(14).allowsHitTesting(false)
                }
            }
        }
    }

    private func stepLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .black)).foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
        }
    }

    // MARK: - Prompt building

    private var autoPrompt: String {
        let today = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let todayKey = isoKey(today)
        let healthEntry = store.healthEntryOrNil(for: todayKey)
        let readiness = healthEntry.flatMap { entry -> HealthService.LocalReadiness? in
            let r = HealthService.computeLocalReadiness(
                for: entry,
                history: store.healthEntries,
                profile: store.profile
            )
            return r.components.isEmpty ? nil : r
        }
        let todayWorkouts = selectedRequest == .today ? store.workouts(forDay: today) : []
        let yesterdayWorkouts = selectedRequest == .today ? store.workouts(forDay: yesterday) : []
        let tomorrowWorkouts = selectedRequest == .today ? store.workouts(forDay: tomorrow) : []
        let weeklyWorkouts = store.workouts(forLast7DaysEndingOn: today)
        let todayLogged = selectedRequest == .today ? store.loggedWorkouts(forDay: today) : []
        let yesterdayLogged = selectedRequest == .today ? store.loggedWorkouts(forDay: yesterday) : []
        let tomorrowLogged = selectedRequest == .today ? store.loggedWorkouts(forDay: tomorrow) : []
        let weeklyLogged = store.loggedWorkouts(forLast7DaysEndingOn: today)

        return ClaudeService.buildCopyablePrompt(
            profile: store.profile,
            coaching: store.coaching,
            requestText: requestText,
            healthEntry: healthEntry,
            readiness: readiness,
            todayWorkouts: todayWorkouts,
            yesterdayWorkouts: yesterdayWorkouts,
            tomorrowWorkouts: tomorrowWorkouts,
            weeklyWorkouts: weeklyWorkouts,
            todayLogged: todayLogged,
            yesterdayLogged: yesterdayLogged,
            tomorrowLogged: tomorrowLogged,
            weeklyLogged: weeklyLogged,
            preferences: todayPreferences
        )
    }

    private var requestText: String {
        switch selectedRequest {
        case .today:
            let dayLabel = todayDateString()
            return """
            Сегодня \(dayLabel). Оцени готовность атлета и **скорректируй сегодняшний план** под состояние организма. \
            Обязательно учитывай: факт вчерашней тренировки, место сегодняшнего дня в целевом плане и плановую нагрузку завтра. \
            Если нужно — измени интенсивность, сократи объём, замени тип тренировки или предложи отдых. \
            В JSON верни итоговый набор тренировок на сегодня (после твоей коррекции): сохранённые без изменений + изменённые с обновлёнными полями + новые. \
            Поле title и date изменённой тренировки должны совпадать с исходными — это позволит приложению заменить её. Если предлагаешь отдых вместо тренировки — пришли запись с sport=\"rest\". \
            Если тренировку надо удалить целиком — добавь в текст ответа строку формата `УДАЛИТЬ: \"<title>\" \"<yyyy-MM-dd>\"` для каждой такой тренировки.
            """
        case .thisWeek:
            return "Составь план тренировок на эту неделю (\(store.currentWeekRange())). Учти текущее состояние организма."
        case .nextWeek:
            return "Составь план тренировок на следующую неделю (\(store.nextWeekRange())). Учти текущее состояние и тренд недели."
        case .recovery:
            return "Составь восстановительную неделю (\(store.nextWeekRange())) — сниженный объём, только Z1–Z2."
        case .preRace:
            return "Составь пред-соревновательную неделю (\(store.nextWeekRange())) — умеренный объём с активацией."
        }
    }

    private func isoKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func todayDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }

    private func copyPrompt() {
        prefsFocused = false
        pasteFocused = false
        UIPasteboard.general.string = generatedPrompt
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
    }

    private func parseResponse(_ text: String) {
        extractedWorkouts = ClaudeService.shared.extractWorkouts(from: text)
        extractedDeletes  = ClaudeService.extractDeletes(from: text)
        loadedCount  = nil
        deletedCount = nil
    }

    private func loadPlan() {
        var deleted = 0
        for d in extractedDeletes {
            if let target = store.workouts.first(where: { $0.title == d.title && $0.date == d.date }) {
                store.delete(target)
                deleted += 1
            }
        }
        store.addOrReplace(extractedWorkouts)
        loadedCount  = extractedWorkouts.count
        deletedCount = deleted
    }
}
