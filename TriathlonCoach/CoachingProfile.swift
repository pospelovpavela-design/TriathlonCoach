import Foundation
import SwiftUI

// MARK: - Coaching profile (configures the AI prompt)

struct CoachingProfile: Codable, Equatable {

    // MARK: Discipline (sport / load focus)

    enum Discipline: String, Codable, CaseIterable, Identifiable {
        case triathlon, marathon, halfMarathon, running, cycling, swimming, strength, hybrid, custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .triathlon:    return "Триатлон"
            case .marathon:     return "Марафон"
            case .halfMarathon: return "Полумарафон"
            case .running:      return "Бег"
            case .cycling:      return "Велоспорт"
            case .swimming:     return "Плавание"
            case .strength:     return "Силовая"
            case .hybrid:       return "Смешанные нагрузки"
            case .custom:       return "Своя роль"
            }
        }

        var coachRole: String {
            switch self {
            case .triathlon:    return "профессиональный тренер по триатлону"
            case .marathon:     return "профессиональный тренер по марафонской подготовке"
            case .halfMarathon: return "профессиональный тренер по полумарафонской подготовке"
            case .running:      return "профессиональный тренер по бегу"
            case .cycling:      return "профессиональный тренер по велоспорту"
            case .swimming:     return "профессиональный тренер по плаванию"
            case .strength:     return "профессиональный тренер силовой и функциональной подготовки"
            case .hybrid:       return "профессиональный тренер по смешанным нагрузкам (бег, вело, силовая)"
            case .custom:       return "профессиональный тренер"
            }
        }
    }

    // MARK: Methodology

    enum Methodology: String, Codable, CaseIterable, Identifiable {
        case none, fitzgerald8020, seluyanov, fitzgeraldSeluyanov, custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none:                 return "Без методики"
            case .fitzgerald8020:       return "Fitzgerald 80/20"
            case .seluyanov:            return "Селуянов"
            case .fitzgeraldSeluyanov:  return "Fitzgerald 80/20 + Селуянов"
            case .custom:               return "Своя"
            }
        }

        var shortDescription: String {
            switch self {
            case .none:                 return "Без методологических ограничений"
            case .fitzgerald8020:       return "Поляризованный подход: 80% Z1–Z2 / 20% Z4–Z5"
            case .seluyanov:            return "Локальная выносливость, статодинамика, работа на АэП/АнП без закисления"
            case .fitzgeraldSeluyanov:  return "Поляризация по Fitzgerald + силовая база и митохондрии по Селуянову"
            case .custom:               return "Свободный набор принципов"
            }
        }

        var promptDescription: String {
            switch self {
            case .none:
                return ""
            case .fitzgerald8020:
                return "Опирайся на методику Мэтта Фитцджеральда 80/20: примерно 80% общего тренировочного объёма должно проходить в низкоинтенсивных зонах (Z1–Z2, ниже первого вентиляторного порога), 20% — в высокоинтенсивных (Z4–Z5, выше второго порога). Поляризованная модель: минимум работы в «серой зоне» Z3."
            case .seluyanov:
                return "Опирайся на методику В. Н. Селуянова: основа — развитие локальной мышечной выносливости и митохондрий. Аэробная работа преимущественно на уровне аэробного порога (АэП) в Z2. Силовая работа — статодинамика (медленные мышечные волокна) для развития окислительного потенциала. Интервальная работа на АнП — короткие отрезки без закисления (без катастрофического падения pH в мышцах)."
            case .fitzgeraldSeluyanov:
                return """
                Используй комбинацию двух методик:
                • Fitzgerald 80/20 — для распределения интенсивности по неделе: 80% низкая (Z1–Z2), 20% высокая (Z4–Z5), минимум Z3.
                • Селуянов — для построения силовой работы (статодинамика на ОМВ) и аэробной базы (митохондрии, работа на АэП). Интервалы на АнП — без закисления, короткие отрезки.
                Эти методики хорошо сочетаются: поляризация даёт распределение нагрузки, Селуянов — что именно делать в каждой зоне.
                """
            case .custom:
                return ""
            }
        }
    }

    // MARK: Adjustment mode (what the coach should do with the plan)

    enum AdjustmentMode: String, Codable, CaseIterable, Identifiable {
        case adjustWeeks
        case keepPlanAdjustToday
        case both

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .adjustWeeks:         return "Корректировать план на недели"
            case .keepPlanAdjustToday: return "Только сегодняшнюю тренировку"
            case .both:                return "Оба варианта"
            }
        }

        var shortDescription: String {
            switch self {
            case .adjustWeeks:
                return "На основе состояния и нагрузки 7 дней предложи изменения в плане на 1–2 недели вперёд"
            case .keepPlanAdjustToday:
                return "План оставь как есть, скорректируй только сегодняшнюю активность под состояние"
            case .both:
                return "Дай рекомендацию и по сегодняшней активности, и по плану на недели"
            }
        }

        var promptInstruction: String {
            switch self {
            case .adjustWeeks:
                return """
                **Режим корректировки: план на ближайшие недели.**
                На основе текущего состояния атлета и тренировочной нагрузки за последние 7 дней — оцени, нужно ли менять план на ближайшие 1–2 недели. В training_rec подробно опиши:
                • что изменить в плане (объём, интенсивность, конкретные тренировки) и почему;
                • если корректировка не нужна — явно скажи «план оставить без изменений» с обоснованием;
                • что делать с сегодняшней тренировкой в контексте этих изменений.
                """
            case .keepPlanAdjustToday:
                return """
                **Режим корректировки: только сегодняшняя активность.**
                План на ближайшие недели НЕ предлагай менять. В training_rec сосредоточься только на сегодня:
                • выполнить тренировку как запланировано / снизить интенсивность / сократить длительность / заменить тип / отдыхать;
                • дай конкретные параметры (зоны, длительность, RPE).
                """
            case .both:
                return """
                **Режим корректировки: оба варианта.**
                В training_rec дай две части:
                1. Что делать с сегодняшней активностью (конкретно: зоны, длительность, RPE, или отдых).
                2. Нужна ли корректировка плана на ближайшие 1–2 недели (если да — что именно; если нет — почему план остаётся).
                """
            }
        }
    }

    // MARK: Stored fields

    var discipline: Discipline = .triathlon
    var customDisciplineRole: String = ""        // used when discipline == .custom
    var goalDescription: String = ""             // e.g. "Готовлюсь к Московскому марафону"
    var goalDateISO: String? = nil               // yyyy-MM-dd
    var methodology: Methodology = .none
    var customMethodologyNotes: String = ""      // free-form, appended to methodology block
    var adjustmentMode: AdjustmentMode = .adjustWeeks

    // MARK: Derived

    var goalDate: Date? {
        get {
            guard let s = goalDateISO else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s)
        }
        set {
            guard let d = newValue else { goalDateISO = nil; return }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            goalDateISO = f.string(from: d)
        }
    }

    /// Opening "you are X" line for the prompt.
    func coachIntro() -> String {
        let role: String
        if discipline == .custom && !customDisciplineRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            role = customDisciplineRole.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            role = discipline.coachRole
        }
        var sentence = "Ты — \(role)"

        let goal = goalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            var part = goal
            if let date = goalDate {
                let f = DateFormatter()
                f.locale = Locale(identifier: "ru_RU")
                f.dateFormat = "d MMMM yyyy"
                part += " (\(f.string(from: date)))"
            }
            sentence += ", готовишь атлета: \(part)"
        }
        sentence += "."
        return sentence
    }

    /// Methodology section lines (or nil if nothing configured).
    func methodologyBlock() -> String? {
        var parts: [String] = []
        let preset = methodology.promptDescription
        if !preset.isEmpty { parts.append(preset) }
        let custom = customMethodologyNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            parts.append("Дополнительные принципы: \(custom)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Short summary used in inline UI cards.
    var summaryLine: String {
        var parts: [String] = [discipline.displayName]
        if methodology != .none { parts.append(methodology.displayName) }
        switch adjustmentMode {
        case .adjustWeeks:         parts.append("план: недели")
        case .keepPlanAdjustToday: parts.append("план: только сегодня")
        case .both:                parts.append("план: оба")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Coaching Profile Sheet

struct CoachingProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    let initial: CoachingProfile
    let onSave: (CoachingProfile) -> Void

    @State private var draft: CoachingProfile
    @State private var hasGoalDate: Bool

    init(initial: CoachingProfile, onSave: @escaping (CoachingProfile) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _draft = State(initialValue: initial)
        _hasGoalDate = State(initialValue: initial.goalDate != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        introCard
                        disciplineSection
                        goalSection
                        methodologySection
                        adjustmentSection
                        previewSection
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Промт тренера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { onSave(draft); dismiss() }
                        .foregroundColor(.blue).fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Sections

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Эти настройки применяются к промту анализа состояния и могут передаваться в Coach-промт.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineSpacing(2)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var disciplineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Вид спорта / нагрузка")
            VStack(spacing: 6) {
                ForEach(CoachingProfile.Discipline.allCases) { d in
                    optionRow(
                        title: d.displayName,
                        subtitle: d == .custom ? "Введите свою роль ниже" : roleSubtitle(d),
                        selected: draft.discipline == d
                    ) {
                        draft.discipline = d
                    }
                }
            }
            if draft.discipline == .custom {
                TextField("Например: тренер по гребле / hyrox / ...",
                          text: $draft.customDisciplineRole)
                    .foregroundColor(.white).padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Цель / событие")
            VStack(alignment: .leading, spacing: 8) {
                TextField("Например: Московский марафон, цель — выбежать из 3:30",
                          text: $draft.goalDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundColor(.white).padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Toggle(isOn: $hasGoalDate) {
                    Text("Указать дату").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: hasGoalDate) { _, newVal in
                    if !newVal { draft.goalDate = nil }
                    else if draft.goalDate == nil {
                        draft.goalDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())
                    }
                }

                if hasGoalDate {
                    DatePicker(
                        "Дата события",
                        selection: Binding(
                            get: { draft.goalDate ?? Date() },
                            set: { draft.goalDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .colorScheme(.dark)
                }
            }
        }
    }

    private var methodologySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Методика подготовки")
            VStack(spacing: 6) {
                ForEach(CoachingProfile.Methodology.allCases) { m in
                    optionRow(
                        title: m.displayName,
                        subtitle: m.shortDescription,
                        selected: draft.methodology == m
                    ) {
                        draft.methodology = m
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Доп. принципы (опционально)")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                TextField("Например: больше плавания, меньше длинных вело...",
                          text: $draft.customMethodologyNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundColor(.white).padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Что должен делать тренер")
            VStack(spacing: 6) {
                ForEach(CoachingProfile.AdjustmentMode.allCases) { mode in
                    optionRow(
                        title: mode.displayName,
                        subtitle: mode.shortDescription,
                        selected: draft.adjustmentMode == mode
                    ) {
                        draft.adjustmentMode = mode
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Превью intro")
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.coachIntro())
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                    .lineSpacing(3)
                if let m = draft.methodologyBlock() {
                    Divider().background(Color.white.opacity(0.1))
                    Text(m)
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                        .lineSpacing(3)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.4)).tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selected ? .blue : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundColor(.white)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(selected ? Color.blue.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.blue.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func roleSubtitle(_ d: CoachingProfile.Discipline) -> String {
        d.coachRole.replacingOccurrences(of: "профессиональный тренер ", with: "")
    }
}
