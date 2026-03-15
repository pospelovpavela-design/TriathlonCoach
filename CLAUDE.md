# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `TriathlonCoach.xcodeproj` in Xcode. Requires:
- iOS 17+ deployment target (WorkoutKit requires iOS 17+)
- Paired Apple Watch running watchOS 10+ for WorkoutKit functionality
- HealthKit entitlements — already configured in `TriathlonCoach.entitlements`

Build from Xcode: `Cmd+B`. Run on device: `Cmd+R` (WorkoutKit does not work in the Simulator).

Tests: `Cmd+U` or via `xcodebuild test -scheme TriathlonCoach -destination 'platform=iOS Simulator,name=iPhone 15'`

## Architecture

**No external dependencies.** Pure SwiftUI + SwiftData (but SwiftData is unused — persistence is manual JSON).

### State & Persistence

`AppStore` (`AppStore.swift`) is the single source of truth — `@StateObject` created in `TriathlonCoachApp` and injected via `.environmentObject`. It owns the `workouts` array and `profile`, persists both to the app's Documents directory (`workouts_store.json`, `athlete_profile` in UserDefaults). All mutations go through `AppStore`.

`WorkoutKitManager` (`WorkoutKitManager.swift`) is a separate `@StateObject` injected the same way. It handles Apple Watch scheduling via WorkoutKit. Indoor sports (`bike_indoor`, `run_indoor`, `strength`, `core`) use `.indoor` location; all others use `.outdoor`. Sports `rest`, `mobility`, `stretch` are excluded from Watch scheduling.

`WorkoutLoader` is a legacy helper — its `demoWorkouts()` static method is used as the fallback when no JSON files exist on device.

### Data Flow: Claude → Plan

1. `ChatView` builds a copyable text prompt via `ClaudeService.buildCopyablePrompt()` — **no direct API call**, the user copies the prompt manually to claude.ai
2. User pastes Claude's response back; `ClaudeService.extractWorkouts()` parses the embedded ` ```json ` block
3. Extracted `[WorkoutPlanJSON]` is merged into `AppStore` via `addOrReplace()` (dedup by `stableKey = title + date`)

### Sport Types

All valid values for `WorkoutPlanJSON.sport`:
`run`, `bike`, `swim`, `strength`, `mobility`, `rest`, `bike_indoor`, `run_indoor`, `core`, `stretch`

Adding a new sport type requires updates in: `Models.swift` (`activityType`, `sportIcon`), `ClaudeService.swift` (prompt text), `WorkoutKitManager.swift` (exclusion lists and `indoorSports`), `WorkoutRow.swift` and `WorkoutDetailView.swift` (Watch button visibility), `AnalyticsView.swift` (`sportIcon` helper), `ReportBuilder.swift` (`sportName`, `sportEmoji`).

### HR Zones

Fixed 5-zone system defined in `HRZone.zones` (Models.swift). Zone bounds are hardcoded and not user-configurable. The prompt sent to Claude includes these zones verbatim so the AI generates matching `target_zone` / `intervals[].zone` values.

### Recovery Metrics & Reports

`WorkoutPlanJSON` stores per-workout wellness fields: `hrv_before/after` (ms), `spo2_percent` (0–100), `hr_recovery_60s` (bpm drop), `rpe_actual` (1–10), `sleep_hours`, `sleep_quality` (1–5). All optional for backward compat.

`HealthKitReader` (`HealthKitReader.swift`) — `@MainActor ObservableObject` injected app-wide. Reads HRV (SDNN), SpO2, sleep from `HKHealthStore`. Authorization requested at app start alongside WorkoutKit. Has both per-day and weekly aggregate methods.

`ReportBuilder` (`ReportBuilder.swift`) — pure static struct. Two entry points:
- `workoutReport(_:profile:)` → detailed per-workout text for Claude
- `weekReport(workouts:weekStart:weekEnd:profile:weeklyHRV:weeklySpO2:weeklySleep:nextWeekRange:)` → weekly summary + plan request

Both reports end with a structured Claude prompt including zone reference and a JSON plan request template. Copy to clipboard via `UIPasteboard.general.string`.

`LogWorkoutSheet` (in `AnalyticsView.swift`) expanded with all new fields + "Прочитать из Apple Health" button (auto-fills HRV, SpO2, sleep for the workout date).

### Tab Structure

| Tab | View | Tag |
|-----|------|-----|
| Тренер | `ChatView` | 0 |
| Неделя | `WeekCalendarView` | 1 |
| Итоги | `AnalyticsView` | 2 |
| Настройки | `SettingsView` | 3 |

`store.selectedTab` is used by `AnalyticsView` to programmatically switch to the Coach tab after building an analysis prompt.
