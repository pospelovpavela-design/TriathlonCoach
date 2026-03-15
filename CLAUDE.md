# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

**CLI build and install (preferred for quick iterations):**
```bash
# Build for connected iPhone
xcodebuild -scheme TriathlonCoach -destination 'id=00008110-000C65C13AC1801E' -configuration Debug build

# Install on device (get device ID from: xcrun devicectl list devices)
xcrun devicectl device install app --device 00008110-000C65C13AC1801E \
  "$(xcodebuild -scheme TriathlonCoach -destination 'id=00008110-000C65C13AC1801E' \
     -configuration Debug -showBuildSettings 2>/dev/null \
     | grep ' BUILT_PRODUCTS_DIR' | head -1 | awk '{print $3}')/TriathlonCoach.app"

# Launch (device must be unlocked)
xcrun devicectl device process launch --device 00008110-000C65C13AC1801E com.Pavel.TriathlonCoach
```

**Requirements:** iOS 17+ (WorkoutKit), Apple Watch Ultra/Series 4+ with watchOS 10+ for full functionality. WorkoutKit and HealthKit do not work in Simulator — must build for physical device.

**Xcode build settings pitfall:** `GENERATE_INFOPLIST_FILE = YES` is set, which means `INFOPLIST_KEY_*` entries in `project.pbxproj` override values in `Info.plist`. If adding new HealthKit/privacy usage descriptions, update both `Info.plist` AND the `INFOPLIST_KEY_*` entries in both Debug and Release build configurations in `project.pbxproj`.

## Architecture

**No external dependencies.** Pure SwiftUI. Persistence is manual JSON (not SwiftData despite the import).

### State — Three App-wide Objects

All three are `@StateObject` in `TriathlonCoachApp`, injected via `.environmentObject`:

| Object | File | Responsibility |
|--------|------|---------------|
| `AppStore` | `AppStore.swift` | Single source of truth: `workouts` array + `AthleteProfile`. Persists to Documents/`workouts_store.json` and UserDefaults. All workout mutations go through it. |
| `WorkoutKitManager` | `WorkoutKitManager.swift` | Apple Watch scheduling via WorkoutKit. Indoor sports (`bike_indoor`, `run_indoor`, `strength`, `core`) → `.indoor` location. Sports `rest`, `mobility`, `stretch` excluded from Watch. |
| `HealthKitReader` | `HealthKitReader.swift` | `@MainActor ObservableObject`. Reads HKHealthStore. Authorization requested at app start. |

### Data Model

`WorkoutPlanJSON` (Codable) is the central model. Key optional fields added for post-workout logging:
- Wellness: `hrv_before/after`, `spo2_percent`, `hr_recovery_60s`, `rpe_actual`
- Sleep: `sleep_hours`, `sleep_quality` (1–5), `sleep_deep_hours`, `sleep_rem_hours`, `sleep_core_hours`, `sleep_avg_hr`, `sleep_avg_hrv`
- Actuals: `actual_avg_hr`, `actual_max_hr`, `actual_duration_min`, `actual_distance_m`, `actual_calories`
- `actual_intervals: [ActualInterval]?` — per-interval stats from Apple Watch

All new fields are optional for backward compatibility with existing JSON files.

`IntervalJSON` = planned intervals (from Claude's JSON). `ActualInterval` (Codable) = recorded intervals from HealthKit `HKWorkout.workoutActivities`.

### HealthKitReader Key Methods

**Workout data:**
- `workoutData(sport:on:)` — searches ±1 day, fetches all workouts then filters by `HKWorkoutActivityType` in code (compound predicate is unreliable). Returns `WorkoutHealthData` with duration, HR, distance, calories, and intervals from `HKWorkout.workoutActivities` (iOS 16+ `allStatistics`).
- `hrRecovery60s(after:)` — peak HR (last 3 min of workout) minus HR at 50–90s post-workout.
- `hrvAfterWorkout(endTime:)` — HRV in 5–120 min window after workout end.

**Sleep:** `sleepResult(nightBefore:)` queries 18:00 previous day to 12:00 of given date. **Phase deduplication:** if Apple Watch phase data (values 3,4,5) exists, only those are used — excludes iPhone's legacy value=1 which covers the same period and would cause double-counting.

**Fallback pattern:** `hrvOrYesterday`, `spO2OrYesterday`, `restingHROrYesterday` try the given date then fall back to yesterday.

**`readFromHealth()` in `LogWorkoutSheet`:** Awaits `workoutData` first (sequential) to get real `endTime`, then runs all other queries in parallel. Uses `today` when plan date is in the future. Tries yesterday's sleep as second fallback.

### Data Flow: Claude → Plan

1. `ChatView` → `ClaudeService.buildCopyablePrompt()` builds text — **no API call**, user copies to claude.ai manually
2. User pastes response → `ClaudeService.extractWorkouts()` parses ` ```json ` block
3. `AppStore.addOrReplace()` merges by `stableKey = title + date`

### Reports (ReportBuilder.swift)

Pure static struct, three entry points:
- `workoutReport(_:profile:)` — full per-workout report with plan vs actual intervals, distance/pace (sport-specific), HR analysis, recovery metrics, comprehensive sleep with phases
- `weekReport(...)` — weekly summary + plan request with JSON template
- `dayReport(date:workouts:profile:sleep:hrv:spo2:restingHR:)` — morning wellness + all workouts for the day

All reports end with a structured Claude prompt. Copied to clipboard via `UIPasteboard.general.string`.

### Sport Types

Valid `WorkoutPlanJSON.sport` values:
`run`, `bike`, `swim`, `strength`, `mobility`, `rest`, `bike_indoor`, `run_indoor`, `core`, `stretch`

Adding a new sport requires updates in: `Models.swift` (`activityType`, `sportIcon`), `HealthKitReader.swift` (`hkActivityType`, `distanceType`), `WorkoutKitManager.swift` (exclusion lists, `indoorSports`), `WorkoutRow.swift`, `WorkoutDetailView.swift` (Watch button), `AnalyticsView.swift` (`sportIcon`), `ReportBuilder.swift` (`sportName`, `sportEmoji`), `ClaudeService.swift` (prompt).

### Tab Structure

| Tab | View | Tag |
|-----|------|-----|
| Тренер | `ChatView` | 0 |
| Неделя | `WeekCalendarView` | 1 |
| Итоги | `AnalyticsView` | 2 |
| Настройки | `SettingsView` | 3 |

`store.selectedTab` switches to Coach tab programmatically from AnalyticsView.

### Project File Notes

Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16) — new Swift files in `TriathlonCoach/` are compiled automatically without adding to `project.pbxproj`.
