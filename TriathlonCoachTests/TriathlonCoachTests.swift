import XCTest
@testable import TriathlonCoach

final class WorkoutJSONParsingTests: XCTestCase {

    // MARK: - JSON Parsing

    func test_parseValidWorkoutJSON() throws {
        let json = """
        [{
            "title": "Лёгкий бег Z2",
            "sport": "run",
            "date": "2026-03-11",
            "duration_min": 45,
            "target_zone": "Z2",
            "description": "Аэробная база",
            "intervals": [
                {"duration_min": 10, "zone": "Z1", "note": "Разминка"},
                {"duration_min": 30, "zone": "Z2", "note": "Основная"},
                {"duration_min": 5,  "zone": "Z1", "note": "Заминка"}
            ],
            "tags": ["run", "z2"],
            "rpe_target": 5,
            "planned": true,
            "completed": false,
            "actual_avg_hr": null,
            "actual_duration_min": null,
            "notes_after": ""
        }]
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let workouts = try JSONDecoder().decode([WorkoutPlanJSON].self, from: data)

        XCTAssertEqual(workouts.count, 1)
        let w = workouts[0]
        XCTAssertEqual(w.title, "Лёгкий бег Z2")
        XCTAssertEqual(w.sport, "run")
        XCTAssertEqual(w.date, "2026-03-11")
        XCTAssertEqual(w.duration_min, 45)
        XCTAssertEqual(w.target_zone, "Z2")
        XCTAssertEqual(w.intervals.count, 3)
        XCTAssertFalse(w.completed)
        XCTAssertTrue(w.planned)
        XCTAssertNil(w.actual_avg_hr)
    }

    func test_parseMultipleWorkouts() throws {
        let json = """
        [
            {"title":"Бег","sport":"run","date":"2026-03-11","duration_min":45,"target_zone":"Z2",
             "description":"","intervals":[],"tags":[],"rpe_target":5,"planned":true,"completed":false,
             "actual_avg_hr":null,"actual_duration_min":null,"notes_after":""},
            {"title":"Велосипед","sport":"bike","date":"2026-03-12","duration_min":60,"target_zone":"Z3",
             "description":"","intervals":[],"tags":[],"rpe_target":6,"planned":true,"completed":true,
             "actual_avg_hr":155,"actual_duration_min":58,"notes_after":"Хорошо прошло"}
        ]
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let workouts = try JSONDecoder().decode([WorkoutPlanJSON].self, from: data)

        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(workouts[1].actual_avg_hr, 155)
        XCTAssertEqual(workouts[1].actual_duration_min, 58)
        XCTAssertEqual(workouts[1].notes_after, "Хорошо прошло")
        XCTAssertTrue(workouts[1].completed)
    }

    func test_parseInvalidJSON_returnsEmpty() throws {
        let json = "not a valid json"
        let data = try XCTUnwrap(json.data(using: .utf8))
        let workouts = try? JSONDecoder().decode([WorkoutPlanJSON].self, from: data)
        XCTAssertNil(workouts)
    }
}

// MARK: - ClaudeService JSON Extraction

final class ClaudeServiceExtractionTests: XCTestCase {

    func test_extractFromCodeFence() async {
        let text = """
        Вот твой план на неделю:

        ```json
        [{"title":"Бег","sport":"run","date":"2026-03-11","duration_min":30,"target_zone":"Z2",
          "description":"","intervals":[],"tags":[],"rpe_target":5,"planned":true,"completed":false,
          "actual_avg_hr":null,"actual_duration_min":null,"notes_after":""}]
        ```

        Удачи!
        """
        let result = await ClaudeService.shared.extractWorkouts(from: text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Бег")
    }

    func test_extractFromBareJSON() async {
        let text = """
        Рекомендую следующий план:
        [{"title":"Плавание","sport":"swim","date":"2026-03-13","duration_min":40,"target_zone":"Z2",
          "description":"","intervals":[],"tags":[],"rpe_target":5,"planned":true,"completed":false,
          "actual_avg_hr":null,"actual_duration_min":null,"notes_after":""}]
        Это оптимально для твоего уровня.
        """
        let result = await ClaudeService.shared.extractWorkouts(from: text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sport, "swim")
    }

    func test_extractFromEmptyText_returnsEmpty() async {
        let result = await ClaudeService.shared.extractWorkouts(from: "")
        XCTAssertTrue(result.isEmpty)
    }

    func test_extractFromTextWithoutJSON_returnsEmpty() async {
        let result = await ClaudeService.shared.extractWorkouts(from: "Привет, вот твой план: бегай больше!")
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - HRZone Tests

final class HRZoneTests: XCTestCase {

    func test_allZonesExist() {
        XCTAssertNotNil(HRZone.zone(for: "Z1"))
        XCTAssertNotNil(HRZone.zone(for: "Z2"))
        XCTAssertNotNil(HRZone.zone(for: "Z3"))
        XCTAssertNotNil(HRZone.zone(for: "Z4"))
        XCTAssertNotNil(HRZone.zone(for: "Z5"))
    }

    func test_invalidZoneReturnsNil() {
        XCTAssertNil(HRZone.zone(for: "Z6"))
        XCTAssertNil(HRZone.zone(for: ""))
    }

    func test_zoneRanges() {
        let z2 = HRZone.zone(for: "Z2")!
        XCTAssertEqual(z2.min, 120)
        XCTAssertEqual(z2.max, 145)

        let z4 = HRZone.zone(for: "Z4")!
        XCTAssertEqual(z4.min, 164)
        XCTAssertEqual(z4.max, 175)
    }

    func test_displayRange() {
        let z2 = HRZone.zone(for: "Z2")!
        XCTAssertEqual(z2.displayRange, "120–145 уд/мин")

        let z5 = HRZone.zone(for: "Z5")!
        XCTAssertTrue(z5.displayRange.hasPrefix(">"))
    }
}

// MARK: - WorkoutPlanJSON Helpers

final class WorkoutPlanJSONHelperTests: XCTestCase {

    private func makeWorkout(sport: String = "run", date: String = "2026-03-11") -> WorkoutPlanJSON {
        WorkoutPlanJSON(
            title: "Test", sport: sport, date: date,
            duration_min: 30, target_zone: "Z2", description: "",
            intervals: [], tags: [], rpe_target: nil,
            planned: true, completed: false,
            actual_avg_hr: nil, actual_duration_min: nil, notes_after: ""
        )
    }

    func test_sportIcon_run() {
        XCTAssertEqual(makeWorkout(sport: "run").sportIcon, "figure.run")
    }

    func test_sportIcon_bike() {
        XCTAssertEqual(makeWorkout(sport: "bike").sportIcon, "figure.outdoor.cycle")
    }

    func test_sportIcon_swim() {
        XCTAssertEqual(makeWorkout(sport: "swim").sportIcon, "figure.pool.swim")
    }

    func test_sportIcon_rest() {
        XCTAssertEqual(makeWorkout(sport: "rest").sportIcon, "moon.zzz")
    }

    func test_parsedDate() {
        let w = makeWorkout(date: "2026-03-11")
        let parsed = w.parsedDate
        XCTAssertNotNil(parsed)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: parsed!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 11)
    }

    func test_stableKey() {
        let w = makeWorkout(sport: "run", date: "2026-03-11")
        XCTAssertEqual(w.stableKey, "Test2026-03-11")
    }

    func test_activityType_run() {
        XCTAssertEqual(makeWorkout(sport: "run").activityType, .running)
    }

    func test_activityType_bike() {
        XCTAssertEqual(makeWorkout(sport: "bike").activityType, .cycling)
    }

    func test_activityType_swim() {
        XCTAssertEqual(makeWorkout(sport: "swim").activityType, .swimming)
    }
}

// MARK: - AthleteProfile Tests

final class AthleteProfileTests: XCTestCase {

    func test_claudeContextIncludesName() {
        var profile = AthleteProfile()
        profile.name = "Павел"
        XCTAssertTrue(profile.claudeContext.contains("Павел"))
    }

    func test_claudeContextIncludesHR() {
        var profile = AthleteProfile()
        profile.maxHR = 185
        profile.restingHR = 55
        XCTAssertTrue(profile.claudeContext.contains("185"))
        XCTAssertTrue(profile.claudeContext.contains("55"))
    }

    func test_claudeContextIncludesNotes() {
        var profile = AthleteProfile()
        profile.notes = "Цель — полужелезная дистанция"
        XCTAssertTrue(profile.claudeContext.contains("полужелезная дистанция"))
    }

    func test_claudeContextWithoutNotes_noEmptyLine() {
        var profile = AthleteProfile()
        profile.notes = ""
        XCTAssertFalse(profile.claudeContext.contains("О себе"))
    }
}

// MARK: - Prompt Builder Tests

final class PromptBuilderTests: XCTestCase {

    func test_promptContainsRequestText() {
        let profile = AthleteProfile()
        let prompt = ClaudeService.buildCopyablePrompt(
            profile: profile,
            requestText: "Составь план на неделю 2026-03-11 – 2026-03-17."
        )
        XCTAssertTrue(prompt.contains("2026-03-11"))
        XCTAssertTrue(prompt.contains("2026-03-17"))
    }

    func test_promptContainsJSONFormat() {
        let profile = AthleteProfile()
        let prompt = ClaudeService.buildCopyablePrompt(profile: profile, requestText: "Тест")
        XCTAssertTrue(prompt.contains("```json"))
        XCTAssertTrue(prompt.contains("duration_min"))
        XCTAssertTrue(prompt.contains("target_zone"))
        XCTAssertTrue(prompt.contains("intervals"))
    }

    func test_promptContainsHRZones() {
        let profile = AthleteProfile()
        let prompt = ClaudeService.buildCopyablePrompt(profile: profile, requestText: "Тест")
        XCTAssertTrue(prompt.contains("Z1"))
        XCTAssertTrue(prompt.contains("Z2"))
        XCTAssertTrue(prompt.contains("Z5"))
    }

    func test_promptContainsAthleteProfile() {
        var profile = AthleteProfile()
        profile.name = "Тестовый атлет"
        let prompt = ClaudeService.buildCopyablePrompt(profile: profile, requestText: "Тест")
        XCTAssertTrue(prompt.contains("Тестовый атлет"))
    }
}
