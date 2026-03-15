import Foundation

// MARK: - Chat Message (kept for compatibility)

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: String
    var content: String
}

// MARK: - Service (prompt building + JSON parsing)

actor ClaudeService {

    static let shared = ClaudeService()

    // MARK: - Copyable prompt builder

    static func buildCopyablePrompt(profile: AthleteProfile, requestText: String) -> String {
        """
        Ты — профессиональный тренер по триатлону. \(requestText)

        Профиль атлета:
        \(profile.claudeContext)

        Пульсовые зоны:
        • Z1: до 119 уд/мин — восстановление
        • Z2: 120–145 уд/мин — аэробная база
        • Z3: 146–163 уд/мин — аэробный порог
        • Z4: 164–175 уд/мин — анаэробный порог
        • Z5: 176+ уд/мин — максимум

        Виды спорта (только эти значения в поле "sport"): run, bike, swim, strength, mobility, rest, bike_indoor, run_indoor, core, stretch

        ВАЖНО: В ответе обязательно включи JSON-блок строго в таком формате:
        ```json
        [
          {
            "title": "Название тренировки",
            "sport": "run",
            "date": "yyyy-MM-dd",
            "duration_min": 45,
            "target_zone": "Z2",
            "description": "Описание тренировки",
            "intervals": [
              {"duration_min": 10, "zone": "Z1", "note": "Разминка"},
              {"duration_min": 30, "zone": "Z2", "note": "Основная часть"},
              {"duration_min": 5, "zone": "Z1", "note": "Заминка"}
            ],
            "tags": ["run", "z2"],
            "rpe_target": 6,
            "planned": true,
            "completed": false,
            "actual_avg_hr": null,
            "actual_duration_min": null,
            "notes_after": ""
          }
        ]
        ```
        Отвечай на русском языке.
        """
    }

    // MARK: - JSON extraction

    func extractWorkouts(from text: String) -> [WorkoutPlanJSON] {
        if let json = extractFromCodeFence(text),
           let workouts = decode(json) { return workouts }
        if let start = text.firstIndex(of: "["),
           let end = text.lastIndex(of: "]") {
            let jsonStr = String(text[start...end])
            if let workouts = decode(jsonStr) { return workouts }
        }
        return []
    }

    private func extractFromCodeFence(_ text: String) -> String? {
        guard let start = text.range(of: "```json"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decode(_ json: String) -> [WorkoutPlanJSON]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([WorkoutPlanJSON].self, from: data)
    }
}
