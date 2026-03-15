import SwiftUI

// MARK: - Main Health Tab

struct HealthView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var healthReader: HealthKitReader

    @State private var selectedDayKey: HealthDayKey?

    private var recentDayKeys: [String] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return (0..<30).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date()).map { fmt.string(from: $0) }
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 0) {
                        trendSection
                        ForEach(recentDayKeys.reversed(), id: \.self) { key in
                            HealthDayCard(
                                date: key,
                                entry: store.healthEntryOrNil(for: key)
                            ) { selectedDayKey = HealthDayKey(id: key) }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .sheet(item: $selectedDayKey) { key in
            HealthDaySheet(
                entry: store.healthEntryOrNil(for: key.id) ?? HealthDayEntry(date: key.id),
                plannedWorkouts: store.workouts(forDay: isoDate(key.id) ?? Date())
            ) { updated in
                store.updateHealthEntry(updated)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ЗДОРОВЬЕ").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)).tracking(4)
                Text("Мониторинг и анализ").font(.system(size: 20, weight: .black)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    // MARK: - Trend Mini Charts

    private var trendSection: some View {
        let last14 = Array(recentDayKeys.suffix(14))
        let entries = last14.map { store.healthEntryOrNil(for: $0) }
        let hrvVals = entries.map { $0?.hrv.map { Double($0) } ?? nil }
        let readVals = entries.map { $0?.aiReadinessScore.map { Double($0) } ?? nil }

        return VStack(spacing: 8) {
            if hrvVals.compactMap({ $0 }).count >= 2 {
                HealthTrendChart(title: "HRV (мс)", values: hrvVals, color: Color(red: 0.23, green: 0.78, blue: 0.9))
                    .padding(.horizontal, 16)
            }
            if readVals.compactMap({ $0 }).count >= 2 {
                HealthTrendChart(title: "Готовность", values: readVals, color: Color(red: 0.13, green: 0.77, blue: 0.37))
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 12)
    }

    private func isoDate(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}

// Used for .sheet(item:) — stable identity by date string
struct HealthDayKey: Identifiable { let id: String }

// MARK: - Trend Chart (bar sparkline)

struct HealthTrendChart: View {
    let title: String
    let values: [Double?]
    let color: Color

    private var maxVal: Double { values.compactMap { $0 }.max() ?? 1 }
    private var minVal: Double { values.compactMap { $0 }.min() ?? 0 }

    @ViewBuilder
    private func barView(for val: Double?) -> some View {
        let fraction: Double = {
            guard let v = val else { return 0 }
            let range = maxVal - minVal
            guard range > 0 else { return 0.5 }
            return (v - minVal) / range
        }()
        RoundedRectangle(cornerRadius: 2)
            .fill(val != nil ? color.opacity(0.4 + 0.6 * fraction) : Color.white.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: val != nil ? max(4, 36 * fraction + 4) : 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.35)).tracking(2)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                    barView(for: val)
                }
            }
            .frame(height: 40)
            if let latest = values.reversed().first(where: { $0 != nil }), let v = latest {
                Text(String(format: "%.0f", v))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(color.opacity(0.9))
            }
        }
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Day Card (compact row)

struct HealthDayCard: View {
    let date: String
    let entry: HealthDayEntry?
    let onTap: () -> Void

    private var isToday: Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date).map { Calendar.current.isDateInToday($0) } ?? false
    }
    private var label: String {
        let f1 = DateFormatter(); f1.locale = Locale(identifier: "en_US_POSIX"); f1.dateFormat = "yyyy-MM-dd"
        guard let d = f1.date(from: date) else { return date }
        let f2 = DateFormatter(); f2.locale = Locale(identifier: "ru_RU"); f2.dateFormat = "EEE, d MMM"
        return f2.string(from: d).capitalized
    }
    private var score: Int? { entry?.aiReadinessScore }
    private var rc: (r: Double, g: Double, b: Double) { HealthService.readinessColor(score: score) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Score circle
                ZStack {
                    Circle()
                        .fill(Color(red: rc.r, green: rc.g, blue: rc.b).opacity(0.15))
                        .frame(width: 44, height: 44)
                    if let s = score {
                        Text("\(s)").font(.system(size: 14, weight: .black))
                            .foregroundColor(Color(red: rc.r, green: rc.g, blue: rc.b))
                    } else {
                        Image(systemName: entry?.hasData == true ? "heart.fill" : "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(entry?.hasData == true ? 0.5 : 0.2))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(label).font(.system(size: 13, weight: isToday ? .bold : .medium))
                            .foregroundColor(isToday ? .blue : .white)
                        if isToday {
                            Text("СЕГОДНЯ").font(.system(size: 9, weight: .black))
                                .foregroundColor(.blue).tracking(1)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if let s = entry?.aiStatus {
                            Text(s).font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(red: rc.r, green: rc.g, blue: rc.b).opacity(0.9))
                        }
                    }
                    if let e = entry, e.hasData {
                        HStack(spacing: 10) {
                            if let v = e.hrv       { chip("HRV \(v)", .cyan) }
                            if let v = e.restingHR { chip("♥ \(v)", .red) }
                            if let v = e.weight    { chip(String(format: "%.1fкг", v), .orange) }
                            if let v = e.sleepHours { chip(String(format: "%.1fч", v), .indigo) }
                        }
                    } else {
                        Text("Нет данных · нажмите для ввода")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.25))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.2))
            }
            .padding(12)
            .background(isToday ? Color.blue.opacity(0.07) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isToday ? Color.blue.opacity(0.25) : Color.white.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .medium))
            .foregroundColor(color.opacity(0.9))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Day Sheet (full entry + AI analysis)

struct HealthDaySheet: View {
    @State var entry: HealthDayEntry
    let plannedWorkouts: [WorkoutPlanJSON]
    let onSave: (HealthDayEntry) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var healthReader: HealthKitReader
    @EnvironmentObject var store: AppStore

    // Biometrics
    @State private var hrv = ""
    @State private var restingHR = ""
    @State private var spo2 = ""
    @State private var wristTemp = ""
    @State private var weight = ""
    @State private var systolic = ""
    @State private var diastolic = ""

    // Sleep
    @State private var sleepHours = ""
    @State private var sleepQuality = 3
    @State private var hasSleepQuality = false
    @State private var sleepDeep = ""
    @State private var sleepRem = ""
    @State private var sleepCore = ""
    @State private var sleepAvgHR = ""
    @State private var sleepAvgHRV = ""

    // Nutrition
    @State private var calories = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""

    // Notes
    @State private var notes = ""

    // Health loading
    @State private var isLoadingHealth = false
    @State private var healthStatus: String? = nil

    // AI
    @State private var promptCopied = false
    @State private var hasGeneratedPrompt = false
    @State private var pasteText = ""
    @State private var showPasteArea = false
    @State private var parseError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Title
                        Text(entry.formattedDate)
                            .font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                        // Read from Health
                        readHealthButton
                        if let status = healthStatus {
                            Text(status).font(.system(size: 12)).foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Biometrics
                        sectionHeader("Биометрика")
                        HStack(spacing: 12) {
                            inputField("HRV (мс)", hint: "напр. 52", value: $hrv)
                            inputField("Пульс покоя", hint: "уд/мин", value: $restingHR)
                        }
                        HStack(spacing: 12) {
                            inputField("SpO2 (%)", hint: "напр. 97", value: $spo2)
                            inputField("Темп. запястья (±°C)", hint: "напр. +0.3", value: $wristTemp)
                        }
                        HStack(spacing: 12) {
                            inputField("Вес (кг)", hint: "напр. 75.2", value: $weight)
                                .keyboardType(.decimalPad)
                            inputField("Давление (сист.)", hint: "напр. 120", value: $systolic)
                        }
                        HStack(spacing: 12) {
                            inputField("Давление (диаст.)", hint: "напр. 80", value: $diastolic)
                            Spacer()
                        }

                        // Sleep
                        sectionHeader("Сон прошлой ночью")
                        HStack(spacing: 12) {
                            inputField("Общее (ч)", hint: "напр. 7.5", value: $sleepHours)
                                .keyboardType(.decimalPad)
                            inputField("HRV во сне (мс)", hint: "напр. 58", value: $sleepAvgHRV)
                        }
                        HStack(spacing: 12) {
                            inputField("Глубокий (ч)", hint: "напр. 1.5", value: $sleepDeep)
                                .keyboardType(.decimalPad)
                            inputField("REM (ч)", hint: "напр. 2.0", value: $sleepRem)
                                .keyboardType(.decimalPad)
                            inputField("Core (ч)", hint: "напр. 3.5", value: $sleepCore)
                                .keyboardType(.decimalPad)
                        }
                        HStack(spacing: 12) {
                            inputField("Пульс во сне", hint: "уд/мин", value: $sleepAvgHR)
                            Spacer()
                        }
                        sleepQualityPicker

                        // Nutrition
                        sectionHeader("Питание (за вчера)")
                        HStack(spacing: 12) {
                            inputField("Калории (ккал)", hint: "напр. 2400", value: $calories)
                            inputField("Белки (г)", hint: "напр. 150", value: $protein)
                                .keyboardType(.decimalPad)
                        }
                        HStack(spacing: 12) {
                            inputField("Жиры (г)", hint: "напр. 80", value: $fat)
                                .keyboardType(.decimalPad)
                            inputField("Углеводы (г)", hint: "напр. 250", value: $carbs)
                                .keyboardType(.decimalPad)
                        }

                        // Notes
                        sectionHeader("Заметки")
                        TextField("Самочувствие, симптомы...", text: $notes, axis: .vertical)
                            .lineLimit(3).foregroundColor(.white)
                            .padding(12).background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        // AI Analysis section
                        aiSection

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Здоровье").navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Read from Health

    private var readHealthButton: some View {
        Button(action: { Task { await readFromHealth() } }) {
            HStack(spacing: 8) {
                if isLoadingHealth { ProgressView().tint(.white).scaleEffect(0.8) }
                else { Image(systemName: "heart.text.clipboard") }
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

    // MARK: - Sleep Quality Picker

    private var sleepQualityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Качество сна").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button(action: { sleepQuality = i; hasSleepQuality = true }) {
                        Text(i <= sleepQuality && hasSleepQuality ? "★" : "☆")
                            .font(.system(size: 26))
                            .foregroundColor(i <= sleepQuality && hasSleepQuality ? .yellow : .white.opacity(0.3))
                    }
                }
                if hasSleepQuality {
                    Text("\(sleepQuality)/5").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(14).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(spacing: 12) {
            sectionHeader("AI-Анализ готовности")

            // Show stored analysis
            if entry.hasAIAnalysis {
                aiAnalysisCard
            }

            // Generate prompt button
            Button(action: { generatePrompt() }) {
                HStack(spacing: 8) {
                    Image(systemName: promptCopied ? "checkmark.circle.fill" : "sparkles")
                    Text(promptCopied ? "Промт скопирован!" : (entry.hasAIAnalysis ? "Обновить анализ" : "Анализировать"))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Group {
                    if promptCopied {
                        Color.green.opacity(0.6)
                    } else {
                        LinearGradient(colors: [Color(red: 0.5, green: 0.2, blue: 0.9), Color(red: 0.3, green: 0.1, blue: 0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                })
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if hasGeneratedPrompt {
                Button(action: { withAnimation { showPasteArea.toggle() } }) {
                    HStack {
                        Image(systemName: showPasteArea ? "chevron.up" : "chevron.down")
                        Text(showPasteArea ? "Скрыть поле вставки" : "Вставить ответ от Claude")
                    }
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if showPasteArea {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $pasteText)
                            .foregroundColor(.white)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 120)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                Group {
                                    if pasteText.isEmpty {
                                        Text("Вставьте JSON-ответ от Claude сюда...")
                                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.25))
                                            .padding(16)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            .allowsHitTesting(false)
                                    }
                                }
                            )

                        if let err = parseError {
                            Text(err).font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
                        }

                        Button(action: { applyAIResponse() }) {
                            Text("Применить анализ")
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var aiAnalysisCard: some View {
        let rc = HealthService.readinessColor(score: entry.aiReadinessScore)
        let scoreColor = Color(red: rc.r, green: rc.g, blue: rc.b)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(scoreColor.opacity(0.15)).frame(width: 52, height: 52)
                    VStack(spacing: 0) {
                        Text("\(entry.aiReadinessScore ?? 0)")
                            .font(.system(size: 20, weight: .black)).foregroundColor(scoreColor)
                        Text("из 100").font(.system(size: 9)).foregroundColor(scoreColor.opacity(0.7))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let s = entry.aiStatus {
                        Text(s.capitalized).font(.system(size: 16, weight: .bold)).foregroundColor(scoreColor)
                    }
                    if let ts = entry.aiGeneratedAt {
                        Text(ts).font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                    }
                }
                Spacer()
            }

            if let summary = entry.aiSummary {
                Text(summary).font(.system(size: 13)).foregroundColor(.white.opacity(0.8)).lineSpacing(3)
            }

            if let rec = entry.aiTrainingRec {
                recRow(icon: "figure.run", title: "Тренировка", text: rec, color: .blue)
            }
            if let rec = entry.aiNutritionRec {
                recRow(icon: "fork.knife", title: "Питание", text: rec, color: .orange)
            }
            if let rec = entry.aiRecoveryRec {
                recRow(icon: "moon.zzz.fill", title: "Восстановление", text: rec, color: .purple)
            }
            if let warnings = entry.aiWarnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundColor(.yellow)
                        Text(w).font(.system(size: 12)).foregroundColor(.yellow.opacity(0.9))
                    }
                }
            }
        }
        .padding(14)
        .background(scoreColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(scoreColor.opacity(0.2), lineWidth: 1))
    }

    private func recRow(icon: String, title: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(color.opacity(0.8))
                Text(text).font(.system(size: 12)).foregroundColor(.white.opacity(0.75)).lineSpacing(2)
            }
        }
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
                .keyboardType(.numberPad)
        }
    }

    // MARK: - Load Existing

    private func loadExisting() {
        hrv       = entry.hrv.map { "\($0)" } ?? ""
        restingHR = entry.restingHR.map { "\($0)" } ?? ""
        spo2      = entry.spo2.map { "\(Int($0))" } ?? ""
        wristTemp = entry.wristTemperatureDelta.map { String(format: "%.2f", $0) } ?? ""
        weight    = entry.weight.map { String(format: "%.1f", $0) } ?? ""
        systolic  = entry.systolicBP.map { "\($0)" } ?? ""
        diastolic = entry.diastolicBP.map { "\($0)" } ?? ""

        sleepHours = entry.sleepHours.map { String(format: "%.1f", $0) } ?? ""
        sleepDeep  = entry.sleepDeepHours.map { String(format: "%.1f", $0) } ?? ""
        sleepRem   = entry.sleepRemHours.map  { String(format: "%.1f", $0) } ?? ""
        sleepCore  = entry.sleepCoreHours.map { String(format: "%.1f", $0) } ?? ""
        sleepAvgHR = entry.sleepAvgHR.map { "\($0)" } ?? ""
        sleepAvgHRV = entry.sleepAvgHRV.map { String(format: "%.0f", $0) } ?? ""
        if let q = entry.sleepQuality { sleepQuality = q; hasSleepQuality = true }

        calories = entry.caloriesConsumed.map { "\($0)" } ?? ""
        protein  = entry.proteinG.map { String(format: "%.0f", $0) } ?? ""
        fat      = entry.fatG.map { String(format: "%.0f", $0) } ?? ""
        carbs    = entry.carbsG.map { String(format: "%.0f", $0) } ?? ""
        notes    = entry.notes ?? ""
    }

    // MARK: - Read from Apple Health

    private func readFromHealth() async {
        guard let date = entry.parsedDate else { return }
        isLoadingHealth = true

        async let sl  = healthReader.sleepResult(nightBefore: date)
        async let wt  = healthReader.wristTemperatureDelta(for: date)
        async let bw  = healthReader.bodyWeight(for: date)
        async let bp  = healthReader.bloodPressure(for: date)
        async let hrv = healthReader.hrvOrYesterday(for: date)
        async let rhr = healthReader.restingHROrYesterday(for: date)
        async let sp  = healthReader.spO2OrYesterday(for: date)
        async let nut = healthReader.nutrition(for: date)

        let (sleep, temp, bodyWt, pressure, hrvVal, rhrVal, spVal, nutData) =
            await (sl, wt, bw, bp, hrv, rhr, sp, nut)

        if let v = hrvVal,   self.hrv.isEmpty       { self.hrv       = "\(Int(v))" }
        if let v = rhrVal,   restingHR.isEmpty       { restingHR      = "\(Int(v))" }
        if let v = spVal,    spo2.isEmpty            { spo2           = "\(Int(v))" }
        if let v = temp,     wristTemp.isEmpty       { wristTemp      = String(format: "%.2f", v) }
        if let v = bodyWt,   weight.isEmpty          { weight         = String(format: "%.1f", v) }
        if let s = pressure.systolic,  systolic.isEmpty  { systolic   = "\(s)" }
        if let d = pressure.diastolic, diastolic.isEmpty { diastolic  = "\(d)" }

        if let sl = sleep {
            if sleepHours.isEmpty { sleepHours = String(format: "%.1f", sl.totalHours) }
            if sleepDeep.isEmpty  && sl.deepHours > 0 { sleepDeep = String(format: "%.1f", sl.deepHours) }
            if sleepRem.isEmpty   && sl.remHours  > 0 { sleepRem  = String(format: "%.1f", sl.remHours)  }
            if sleepCore.isEmpty  && sl.coreHours > 0 { sleepCore = String(format: "%.1f", sl.coreHours) }
            if let hr  = sl.avgHR,  sleepAvgHR.isEmpty  { sleepAvgHR  = "\(Int(hr))"  }
            if let hv  = sl.avgHRV, sleepAvgHRV.isEmpty { sleepAvgHRV = "\(Int(hv))"  }
        }
        if let c = nutData.calories, calories.isEmpty { calories = "\(c)" }
        if let p = nutData.proteinG, protein.isEmpty  { protein  = String(format: "%.0f", p) }
        if let f = nutData.fatG,     fat.isEmpty      { fat      = String(format: "%.0f", f) }
        if let ch = nutData.carbsG,  carbs.isEmpty    { carbs    = String(format: "%.0f", ch) }

        isLoadingHealth = false

        var found: [String] = []
        if hrvVal  != nil   { found.append("HRV") }
        if spVal   != nil   { found.append("SpO2") }
        if bodyWt  != nil   { found.append("вес") }
        if pressure.systolic != nil { found.append("давление") }
        if sleep   != nil   { found.append("сон") }
        if temp    != nil   { found.append("температура") }
        if nutData.calories != nil  { found.append("питание") }

        healthStatus = found.isEmpty
            ? "Нет данных в Apple Health"
            : "Загружено: \(found.joined(separator: ", "))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { healthStatus = nil }
    }

    // MARK: - Generate Prompt

    private func generatePrompt() {
        let current = buildEntry()
        entry = current
        onSave(current)  // persist current state without dismissing
        let prompt = HealthService.buildPrompt(
            entry: buildEntry(),
            profile: store.profile,
            plannedWorkouts: plannedWorkouts
        )
        UIPasteboard.general.string = prompt
        withAnimation { promptCopied = true }
        hasGeneratedPrompt = true
        showPasteArea = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { promptCopied = false } }
    }

    // MARK: - Apply AI Response

    private func applyAIResponse() {
        guard let analysis = HealthService.parseAIResponse(pasteText) else {
            parseError = "Не удалось распознать JSON. Убедитесь что вставили ответ целиком."
            return
        }
        parseError = nil
        var updated = buildEntry()
        updated.aiReadinessScore = analysis.score
        updated.aiStatus         = analysis.status
        updated.aiSummary        = analysis.summary
        updated.aiTrainingRec    = analysis.trainingRec
        updated.aiNutritionRec   = analysis.nutritionRec
        updated.aiRecoveryRec    = analysis.recoveryRec
        updated.aiWarnings       = analysis.warnings
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        updated.aiGeneratedAt = fmt.string(from: Date())
        entry = updated
        onSave(updated)
        pasteText = ""
        showPasteArea = false
        hasGeneratedPrompt = false
    }

    // MARK: - Save

    private func buildEntry() -> HealthDayEntry {
        var e = entry
        e.hrv                   = Int(hrv)
        e.restingHR             = Int(restingHR)
        e.spo2                  = Double(spo2)
        e.wristTemperatureDelta = Double(wristTemp)
        e.weight                = Double(weight)
        e.systolicBP            = Int(systolic)
        e.diastolicBP           = Int(diastolic)
        e.sleepHours            = Double(sleepHours)
        e.sleepQuality          = hasSleepQuality ? sleepQuality : nil
        e.sleepDeepHours        = Double(sleepDeep)
        e.sleepRemHours         = Double(sleepRem)
        e.sleepCoreHours        = Double(sleepCore)
        e.sleepAvgHR            = Int(sleepAvgHR)
        e.sleepAvgHRV           = Double(sleepAvgHRV)
        e.caloriesConsumed      = Int(calories)
        e.proteinG              = Double(protein)
        e.fatG                  = Double(fat)
        e.carbsG                = Double(carbs)
        e.notes                 = notes.isEmpty ? nil : notes
        return e
    }

    private func save() {
        let updated = buildEntry()
        onSave(updated)
        dismiss()
    }
}
