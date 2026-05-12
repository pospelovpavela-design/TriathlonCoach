import SwiftUI

struct TargetPlanView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var healthReader: HealthKitReader

    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var targetName = "Старт"
    @State private var targetDistance = "Олимпийская дистанция"
    @State private var targetPriority = "A"
    @State private var constraints = ""
    @State private var pastedResponse = ""
    @State private var extractedWorkouts: [WorkoutPlanJSON] = []
    @State private var loadedCount: Int?
    @State private var parseStatus: String?
    @State private var copied = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case distance
        case priority
        case constraints
        case paste
    }

    private var generatedPrompt: String {
        buildTargetPrompt()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                targetSection
                promptSection
                pasteSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focusedField = nil }
                    .fontWeight(.semibold)
            }
        }
        .task {
            await store.refreshLoggedWorkouts(daysBack: 27, healthReader: healthReader)
        }
        .onChange(of: pastedResponse) { _, newValue in
            parseResponse(newValue)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ЦЕЛЬ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(4)
                Text("План до даты")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Параметры цели")

            VStack(spacing: 12) {
                fieldRow("Название цели", text: $targetName, field: .name)
                fieldRow("Дистанция / формат", text: $targetDistance, field: .distance)

                HStack(spacing: 12) {
                    DatePicker(
                        "Дата",
                        selection: $targetDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .foregroundColor(.white)
                    .tint(.blue)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Приоритет")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("A", text: $targetPriority)
                            .focused($focusedField, equals: .priority)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.characters)
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .frame(width: 96)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ограничения и вводные")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $constraints)
                            .focused($focusedField, equals: .constraints)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(minHeight: 78, maxHeight: 130)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))

                        if constraints.isEmpty {
                            Text("Доступные дни, поездки, травмы, бассейн, станок, желаемый объём...")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.22))
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel("1", "Скопируй промт для Claude")

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
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(copied ? Color.green.opacity(0.85) : Color.blue.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel("2", "Вставь JSON-план и примени")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedResponse)
                    .focused($focusedField, equals: .paste)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 140, maxHeight: 280)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))

                if pastedResponse.isEmpty {
                    Text("Вставь ответ Claude с JSON-массивом тренировок...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.22))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            applyPromptButton

            if let parseStatus {
                Text(parseStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            if !extractedWorkouts.isEmpty {
                applyBanner
            }
        }
    }

    private var applyPromptButton: some View {
        let hasText = !pastedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isLoaded = loadedCount != nil
        let title: String = {
            if let loadedCount {
                return "Применено: \(loadedCount)"
            }
            if extractedWorkouts.isEmpty {
                return "Распознать и применить план"
            }
            return "Применить \(extractedWorkouts.count) тренировок"
        }()

        return Button(action: applyPastedPlan) {
            HStack {
                Image(systemName: isLoaded ? "checkmark.circle.fill" : "calendar.badge.plus")
                Text(title)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(hasText && !isLoaded ? Color.green.opacity(0.85) : Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!hasText || isLoaded)
    }

    private var applyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 20))
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Найдено: \(extractedWorkouts.count) трен.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                if let n = loadedCount {
                    Text("Загружено \(n)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Text("\(dateRangeLabel) · \(totalPlannedHours)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            if loadedCount != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.30), lineWidth: 1))
    }

    private var dateRangeLabel: String {
        let dates = extractedWorkouts.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else { return "без дат" }
        return first == last ? first : "\(first) – \(last)"
    }

    private var totalPlannedHours: String {
        let minutes = extractedWorkouts.reduce(0) { $0 + $1.duration_min }
        return String(format: "%.1f ч", Double(minutes) / 60.0)
    }

    private func fieldRow(_ label: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
            TextField(label, text: text)
                .focused($focusedField, equals: field)
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .tracking(3)
    }

    private func stepLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private func copyPrompt() {
        focusedField = nil
        UIPasteboard.general.string = generatedPrompt
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }

    private func parseResponse(_ text: String) {
        loadedCount = nil
        parseStatus = nil
        Task {
            let workouts = await ClaudeService.shared.extractWorkouts(from: text)
            guard text == pastedResponse else { return }
            extractedWorkouts = workouts
            if workouts.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parseStatus = "JSON-план пока не распознан. Проверь, что ответ содержит массив тренировок."
            }
        }
    }

    private func applyPastedPlan() {
        focusedField = nil
        let text = pastedResponse
        parseStatus = "Распознаю JSON-план..."
        Task {
            let workouts = await ClaudeService.shared.extractWorkouts(from: text)
            guard text == pastedResponse else { return }
            extractedWorkouts = workouts
            if workouts.isEmpty {
                loadedCount = nil
                parseStatus = "JSON-план не найден. Вставь полный ответ Claude с массивом тренировок."
                return
            }
            store.addOrReplace(workouts)
            loadedCount = workouts.count
            parseStatus = nil
        }
    }

    private func buildTargetPrompt() -> String {
        let today = Date()
        let startKey = isoKey(today)
        let targetKey = isoKey(targetDate)
        let healthEntry = store.healthEntryOrNil(for: startKey)
        let readiness = healthEntry.flatMap { entry -> HealthService.LocalReadiness? in
            let r = HealthService.computeLocalReadiness(
                for: entry,
                history: store.healthEntries,
                profile: store.profile
            )
            return r.components.isEmpty ? nil : r
        }
        let weeklyWorkouts = store.workouts(forLast7DaysEndingOn: today)
        let weeklyLogged = store.loggedWorkouts(forLast7DaysEndingOn: today)

        var prompt = ClaudeService.buildCopyablePrompt(
            profile: store.profile,
            coaching: store.coaching,
            requestText: targetRequestText(startKey: startKey, targetKey: targetKey),
            healthEntry: healthEntry,
            readiness: readiness,
            weeklyWorkouts: weeklyWorkouts,
            weeklyLogged: weeklyLogged,
            preferences: constraints
        )

        let future = futureWorkouts(until: targetKey)
        if !future.isEmpty {
            prompt += "\n\n## Уже запланировано до цели\n"
            prompt += future.map { w in
                "• \(w.date) \(ReportBuilder.sportEmoji(w.sport)) \(w.title) — \(w.duration_min) мин, \(w.target_zone)"
            }.joined(separator: "\n")
            prompt += "\n\nЕсли существующие тренировки нужно заменить, верни новые записи с теми же title и date."
        }

        return prompt
    }

    private func targetRequestText(startKey: String, targetKey: String) -> String {
        let goalName = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let distance = targetDistance.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = targetPriority.trimmingCharacters(in: .whitespacesAndNewlines)
        let days = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: targetDate)).day ?? 1)

        return """
        Сформируй периодизированный план подготовки с \(startKey) до целевой даты \(targetKey).
        Цель: \(goalName.isEmpty ? "старт" : goalName).
        Формат/дистанция: \(distance.isEmpty ? "триатлон" : distance).
        Приоритет цели: \(priority.isEmpty ? "A" : priority).
        До цели: \(days) дней.

        Нужен практический календарный план по дням: тренировки, отдых, разгрузочные недели, подводка к старту.
        Учитывай профиль атлета, методику тренера, текущее состояние организма и фактическую нагрузку последних дней.
        Не перегружай первые недели, увеличивай объём постепенно, оставляй минимум 1 день отдыха/восстановления в неделю.
        В JSON верни тренировки на весь период до цели включительно. Для дней полного отдыха добавляй sport="rest", если это важно для структуры недели.
        """
    }

    private func futureWorkouts(until targetKey: String) -> [WorkoutPlanJSON] {
        let todayKey = isoKey(Date())
        return store.workouts
            .filter { $0.date >= todayKey && $0.date <= targetKey }
            .sorted { $0.date < $1.date }
    }

    private func isoKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
