# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

**Build:**
```bash
cd /Users/pospelovsfamily/Documents/TriathlonCoach
xcodebuild -scheme TriathlonCoach -destination 'id=00008110-000C65C13AC1801E' -configuration Debug build
```

**Install on device:**
```bash
xcrun devicectl device install app --device 00008110-000C65C13AC1801E \
  "$(xcodebuild -scheme TriathlonCoach -destination 'id=00008110-000C65C13AC1801E' \
     -configuration Debug -showBuildSettings 2>/dev/null \
     | grep ' BUILT_PRODUCTS_DIR' | head -1 | awk '{print $3}')/TriathlonCoach.app"
```

**Launch (device must be unlocked):**
```bash
xcrun devicectl device process launch --device 00008110-000C65C13AC1801E com.Pavel.TriathlonCoach
```

**Requirements:** iOS 17+ (WorkoutKit), Apple Watch Ultra/Series 4+ with watchOS 10+ for full functionality. WorkoutKit and HealthKit do not work in Simulator — must build for physical device.

**Xcode build settings pitfall:** `GENERATE_INFOPLIST_FILE = YES` is set, which means `INFOPLIST_KEY_*` entries in `project.pbxproj` override values in `Info.plist`. If adding new HealthKit/privacy usage descriptions, update both `Info.plist` AND the `INFOPLIST_KEY_*` entries in both Debug and Release build configurations in `project.pbxproj`.

**HealthKit authorization pitfall:** Do NOT include `HKCorrelationType(.bloodPressure)` in the `read` types passed to `requestAuthorization`. On iOS 17+ it triggers `_throwIfAuthorizationDisallowedForSharing` → SIGABRT crash at launch. Read blood pressure by querying `HKQuantityType(.bloodPressureSystolic)` and `HKQuantityType(.bloodPressureDiastolic)` directly.

## Architecture

**No external dependencies.** Pure SwiftUI. Persistence is manual JSON (not SwiftData despite the import).

### State — Three App-wide Objects

All three are `@StateObject` in `TriathlonCoachApp`, injected via `.environmentObject`:

| Object | File | Responsibility |
|--------|------|---------------|
| `AppStore` | `AppStore.swift` | Single source of truth: `workouts` array + `healthEntries` array + `AthleteProfile`. Persists to `workouts_store.json` and `health_entries.json`. All mutations go through it. |
| `WorkoutKitManager` | `WorkoutKitManager.swift` | Apple Watch scheduling via WorkoutKit. Indoor sports (`bike_indoor`, `run_indoor`, `strength`, `core`) → `.indoor` location. Sports `rest`, `mobility`, `stretch` excluded from Watch. |
| `HealthKitReader` | `HealthKitReader.swift` | `@MainActor ObservableObject`. Reads HKHealthStore. Authorization requested at app start. |

### Tab Structure

| Tab | View | Tag |
|-----|------|-----|
| Тренер | `ChatView` | 0 |
| Неделя | `WeekCalendarView` | 1 |
| Итоги | `AnalyticsView` | 2 |
| Здоровье | `HealthView` | 3 |
| Настройки | `SettingsView` | 4 |

`store.selectedTab` switches to Coach tab (0) programmatically from AnalyticsView and WorkoutDetailView.

### Data Models

**`WorkoutPlanJSON`** (Codable) is the central workout model. Key optional fields for post-workout logging:
- Wellness: `hrv_before/after`, `spo2_percent`, `hr_recovery_60s`, `rpe_actual`
- Sleep: `sleep_hours`, `sleep_quality` (1–5), `sleep_deep_hours`, `sleep_rem_hours`, `sleep_core_hours`, `sleep_avg_hr`, `sleep_avg_hrv`
- Actuals: `actual_avg_hr`, `actual_max_hr`, `actual_duration_min`, `actual_distance_m`, `actual_calories`
- `actual_intervals: [ActualInterval]?` — per-interval stats from Apple Watch
- `stableKey = title + date` — used for merging/deduplication

**`HealthDayEntry`** (Codable) is the daily health snapshot model:
- Biometrics: `hrv`, `restingHR`, `spo2`, `wristTemperatureDelta` (°C from baseline), `weight` (kg), `systolicBP`/`diastolicBP`
- Sleep: same fields as WorkoutPlanJSON sleep fields
- Nutrition: `caloriesConsumed`, `proteinG`, `fatG`, `carbsG`
- AI Analysis: `aiReadinessScore` (0–100), `aiStatus`, `aiSummary`, `aiTrainingRec`, `aiNutritionRec`, `aiRecoveryRec`, `aiWarnings`
- Keyed by `date` (yyyy-MM-dd string)

**`AthleteProfile`** (Codable, stored in `UserDefaults` under key `"athlete_profile"`):
- `name`, `maxHR`, `restingHR`, `weeklyHoursGoal`, `notes`
- `claudeContext` — formatted string included in every Claude prompt

`IntervalJSON` = planned intervals (from Claude's JSON). `ActualInterval` (Codable) = recorded intervals from HealthKit.

### HealthKitReader Key Methods

**Workout data:**
- `workoutData(sport:on:)` — searches ±1 day, returns single best match `WorkoutHealthData`
- `allWorkoutData(sport:on:)` — returns ALL workouts in ±1 day for multi-select/merge in LogWorkoutSheet
- `hrRecovery60s(after:)` — peak HR (last 3 min of workout) minus HR at 50–90s post-workout
- `hrvAfterWorkout(endTime:)` — HRV in 5–120 min window after workout end

**Sleep:** `sleepResult(nightBefore:)` queries 18:00 previous day to 12:00 of given date. Phase deduplication: Apple Watch values (3,4,5) exclude legacy iPhone value=1.

**Health metrics:**
- `bodyWeight(for:)` — kg from HKQuantityType(.bodyMass)
- `bloodPressure(for:)` — (systolic, diastolic) from HKCorrelationType(.bloodPressure)
- `wristTemperatureDelta(for:)` — °C deviation from HKQuantityType(.appleSleepingWristTemperature)
- `nutrition(for:)` → `NutritionData` — calories, protein, fat, carbs

**Fallback pattern:** `hrvOrYesterday`, `spO2OrYesterday`, `restingHROrYesterday` try given date then fall back to yesterday.

**`readFromHealth()` in `LogWorkoutSheet`:** Calls `allWorkoutData` (returns all found workouts). If multiple found, shows picker with "Объединить все" option. Wellness data always from plan date.

### Data Flow: Claude → Plan

1. `ChatView` → `ClaudeService.buildCopyablePrompt()` builds text — **no API call**, user copies to claude.ai manually
2. User pastes response → `ClaudeService.extractWorkouts()` parses ` ```json ` block
3. `AppStore.addOrReplace()` merges by `stableKey = title + date`

### Data Flow: Health Analysis

1. `HealthView` → user fills metrics or taps "Прочитать из Health"
2. "Анализировать" → `HealthService.buildPrompt()` → copied to clipboard; `hasGeneratedPrompt = true` persists paste area visibility
3. User pastes Claude's JSON response → `HealthService.parseAIResponse()` → stored in `HealthDayEntry`
4. `AppStore.updateHealthEntry()` persists to `health_entries.json`

**AI section state in `HealthDaySheet`:** `promptCopied` is only a 3-second visual flash. `hasGeneratedPrompt` controls whether the paste toggle button stays visible. `showPasteArea` controls the text editor. Never gate paste area visibility on `promptCopied` — it resets automatically.

### Reports (ReportBuilder.swift)

Pure static struct, three entry points:
- `workoutReport(_:profile:)` — full per-workout report with plan vs actual, HR, recovery, sleep
- `weekReport(...)` — weekly summary + plan request with JSON template
- `dayReport(date:workouts:profile:sleep:hrv:spo2:restingHR:)` — morning wellness + workouts

All reports end with a structured Claude prompt. Copied to clipboard via `UIPasteboard.general.string`.

### Health Prompt & Analysis (HealthService.swift)

- `HealthService.buildPrompt(entry:profile:plannedWorkouts:)` — daily health analysis prompt
- `HealthService.parseAIResponse(_:)` — extracts JSON from Claude's response, returns structured fields
- Expected JSON: `{ date, readiness_score (0–100), status, summary, training_rec, nutrition_rec, recovery_rec, warnings[] }`

### Sport Types

Valid `WorkoutPlanJSON.sport` values:
`run`, `bike`, `swim`, `strength`, `mobility`, `rest`, `bike_indoor`, `run_indoor`, `core`, `stretch`

Adding a new sport requires updates in: `Models.swift` (`activityType`, `sportIcon`), `HealthKitReader.swift` (`hkActivityType`, `distanceType`), `WorkoutKitManager.swift` (exclusion lists, `indoorSports`), `WorkoutRow.swift`, `WorkoutDetailView.swift` (Watch button), `AnalyticsView.swift` (`sportIcon`), `ReportBuilder.swift` (`sportName`, `sportEmoji`), `ClaudeService.swift` (prompt).

### Workout Deletion

- `AppStore.delete(_:)` — removes by stableKey, saves
- Available via: long-press contextMenu on rows (calendar + analytics), trash button in WorkoutDetailView toolbar (with confirmation dialog)

### Persistence & Demo Data

- `workouts_store.json` — primary store; falls back to legacy `workouts_updated.json`, then `WorkoutLoader.demoWorkouts()`
- `health_entries.json` — health entries (Documents directory)
- `AthleteProfile` — `UserDefaults` key `"athlete_profile"`

### Project File Notes

Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16) — new Swift files in `TriathlonCoach/` are compiled automatically without adding to `project.pbxproj`.
