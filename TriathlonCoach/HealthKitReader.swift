import Foundation
import Combine
import HealthKit

// MARK: - HealthKit reader for recovery metrics

@MainActor
class HealthKitReader: ObservableObject {

    private let store = HKHealthStore()
    @Published var isAuthorized = false

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: Set<HKObjectType> = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await store.requestAuthorization(toShare: Set<HKSampleType>(), read: types)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Workout data from HKWorkout

    struct WorkoutHealthData {
        struct Interval {
            let number: Int
            let durationMin: Double
            let avgHR: Int?
            let maxHR: Int?
            let distanceM: Double?

            var paceSecPerKm: Double? {
                guard let d = distanceM, d > 0 else { return nil }
                return (durationMin * 60) / (d / 1000)
            }
            var speedKmh: Double? {
                guard let d = distanceM, durationMin > 0 else { return nil }
                return (d / 1000) / (durationMin / 60)
            }
            var paceString: String? {
                guard let p = paceSecPerKm else { return nil }
                return String(format: "%d:%02d /км", Int(p) / 60, Int(p) % 60)
            }
            var speedString: String? {
                guard let s = speedKmh else { return nil }
                return String(format: "%.1f км/ч", s)
            }
        }

        let durationMin: Double
        let avgHR: Int?
        let maxHR: Int?
        let distanceM: Double?
        let calories: Int?
        let startTime: Date
        let endTime: Date
        let intervals: [Interval]

        var paceSecPerKm: Double? {
            guard let d = distanceM, d > 0 else { return nil }
            return (durationMin * 60) / (d / 1000)
        }
        var speedKmh: Double? {
            guard let d = distanceM, durationMin > 0 else { return nil }
            return (d / 1000) / (durationMin / 60)
        }
        var paceString: String? {
            guard let p = paceSecPerKm else { return nil }
            return String(format: "%d:%02d /км", Int(p) / 60, Int(p) % 60)
        }
        var speedString: String? {
            guard let s = speedKmh else { return nil }
            return String(format: "%.1f км/ч", s)
        }
    }

    /// Find HKWorkout for a sport type on a given date and extract stats + intervals
    func workoutData(sport: String, on date: Date) async -> WorkoutHealthData? {
        let (start, end) = dayRange(for: date)
        let datePred = HKQuery.predicateForSamples(withStart: start, end: end)
        let actType = hkActivityType(for: sport)
        let actPred = HKQuery.predicateForWorkouts(with: actType)
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [datePred, actPred])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let wkt: HKWorkout? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred,
                                  limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
        guard let wkt else { return nil }

        let durationMin = wkt.duration / 60

        // HR for whole workout
        let (avgHR, maxHR) = await hrStats(from: wkt.startDate, to: wkt.endDate)

        // Distance
        let distType = distanceType(for: sport)
        var distanceM: Double? = nil
        if let dt = distType {
            distanceM = await statSum(type: dt, from: wkt.startDate, to: wkt.endDate, unit: .meter())
        }

        // Calories
        let calories: Int?
        if let cal = await statSum(type: HKQuantityType(.activeEnergyBurned),
                                    from: wkt.startDate, to: wkt.endDate, unit: .kilocalorie()) {
            calories = Int(cal.rounded())
        } else { calories = nil }

        // Intervals from workout activities (iOS 16+)
        var intervals: [WorkoutHealthData.Interval] = []
        for (idx, activity) in wkt.workoutActivities.enumerated() {
            guard let actEnd = activity.endDate else { continue }
            let dur = actEnd.timeIntervalSince(activity.startDate) / 60
            guard dur >= 0.4 else { continue }  // skip sub-30s transitions

            let hrAvg = activity.allStatistics[HKQuantityType(.heartRate)]?
                .averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            let hrMax = activity.allStatistics[HKQuantityType(.heartRate)]?
                .maximumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))

            var dist: Double? = nil
            if let dt = distType {
                dist = activity.allStatistics[dt]?.sumQuantity()?.doubleValue(for: .meter())
            }
            intervals.append(WorkoutHealthData.Interval(
                number: idx + 1,
                durationMin: dur,
                avgHR: hrAvg.map { Int($0.rounded()) },
                maxHR: hrMax.map { Int($0.rounded()) },
                distanceM: dist
            ))
        }

        return WorkoutHealthData(durationMin: durationMin, avgHR: avgHR, maxHR: maxHR,
                                  distanceM: distanceM, calories: calories,
                                  startTime: wkt.startDate, endTime: wkt.endDate,
                                  intervals: intervals)
    }

    // MARK: - HRV

    /// Latest HRV sample for a given calendar day (ms)
    func hrv(for date: Date) async -> Double? {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let (start, end) = dayRange(for: date)
        return await latestSample(type: type, from: start, to: end, unit: .secondUnit(with: .milli))
    }

    /// All HRV samples (ms) within a date range
    func weeklyHRVValues(from start: Date, to end: Date) async -> [Double] {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        return await allSamples(type: type, from: start, to: end, unit: .secondUnit(with: .milli))
    }

    /// HRV measured in the window 5–120 minutes after workout end (e.g. Breathe session)
    func hrvAfterWorkout(endTime: Date) async -> Double? {
        let windowStart = endTime.addingTimeInterval(5 * 60)
        let windowEnd   = endTime.addingTimeInterval(120 * 60)
        return await latestSample(type: HKQuantityType(.heartRateVariabilitySDNN),
                                   from: windowStart, to: windowEnd,
                                   unit: .secondUnit(with: .milli))
    }

    // MARK: - HR Recovery

    /// Heart rate drop 60 seconds after workout end
    func hrRecovery60s(after endTime: Date) async -> Int? {
        // Peak HR: last 3 minutes of workout
        guard let peakWindow = Calendar.current.date(byAdding: .minute, value: -3, to: endTime) else { return nil }
        let (peakAvg, _) = await hrStats(from: peakWindow, to: endTime)
        guard let peak = peakAvg else { return nil }

        // HR at ~60s after end
        let after50 = endTime.addingTimeInterval(50)
        let after90 = endTime.addingTimeInterval(90)
        let hrAtSamples: [Double] = await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: after50, end: after90)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: HKQuantityType(.heartRate), predicate: pred,
                                   limit: 5, sortDescriptors: [sort]) { _, samples, _ in
                let vals = (samples as? [HKQuantitySample])?
                    .map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) } ?? []
                cont.resume(returning: vals)
            }
            store.execute(q)
        }
        guard !hrAtSamples.isEmpty else { return nil }
        let hr60 = hrAtSamples.reduce(0, +) / Double(hrAtSamples.count)
        let drop = Double(peak) - hr60
        return drop > 0 ? Int(drop.rounded()) : nil
    }

    // MARK: - SpO2

    func spO2Percent(for date: Date) async -> Double? {
        let type = HKQuantityType(.oxygenSaturation)
        let (start, end) = dayRange(for: date)
        guard let v = await statAverage(type: type, from: start, to: end, unit: .percent()) else { return nil }
        return (v * 100).rounded()
    }

    func weeklySpO2Percent(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(.oxygenSaturation)
        guard let v = await statAverage(type: type, from: start, to: end, unit: .percent()) else { return nil }
        return (v * 1000).rounded() / 10
    }

    // MARK: - Resting HR

    func restingHR(for date: Date) async -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        let (start, end) = dayRange(for: date)
        return await latestSample(type: type, from: start, to: end, unit: HKUnit(from: "count/min"))?.rounded()
    }

    func weeklyRestingHRAverage(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        return await statAverage(type: type, from: start, to: end, unit: HKUnit(from: "count/min"))?.rounded()
    }

    // MARK: - Sleep (comprehensive)

    struct SleepResult {
        let totalHours: Double
        let deepHours: Double
        let remHours: Double
        let coreHours: Double
        let avgHR: Double?
        let avgHRV: Double?

        var summary: String {
            var p = [String(format: "%.1fч", totalHours)]
            if deepHours > 0 { p.append(String(format: "глуб. %.1fч", deepHours)) }
            if remHours  > 0 { p.append(String(format: "REM %.1fч",  remHours))  }
            if coreHours > 0 { p.append(String(format: "core %.1fч", coreHours)) }
            if let hr = avgHR { p.append(String(format: "♥ %.0f", hr)) }
            if let hrv = avgHRV { p.append(String(format: "HRV %.0fмс", hrv)) }
            return p.joined(separator: ", ")
        }
    }

    /// Comprehensive sleep: total/phases + avg HR + avg HRV within sleep intervals
    func sleepResult(nightBefore date: Date) async -> SleepResult? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let prevEvening = cal.date(byAdding: .hour, value: -6, to: dayStart) else { return nil }
        let morning = dayStart.addingTimeInterval(3600 * 12)

        let type = HKCategoryType(.sleepAnalysis)
        let pred = HKQuery.predicateForSamples(withStart: prevEvening, end: morning)

        let sleepSamples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred,
                                   limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        guard !sleepSamples.isEmpty else { return nil }

        // rawValue: 1=asleep(legacy), 3=asleepCore, 4=asleepDeep, 5=asleepREM, 6=asleepUnspecified
        var total = 0.0, deep = 0.0, rem = 0.0, core = 0.0
        let asleepSamples = sleepSamples.filter { [1, 3, 4, 5, 6].contains($0.value) }
        for s in asleepSamples {
            let h = s.endDate.timeIntervalSince(s.startDate) / 3600
            total += h
            if s.value == 4 { deep += h }
            if s.value == 5 { rem  += h }
            if s.value == 3 { core += h }
        }
        guard total > 0 else { return nil }

        // HR within sleep intervals
        let hrType = HKQuantityType(.heartRate)
        var allHR: [Double] = []
        for interval in asleepSamples {
            let hrPred = HKQuery.predicateForSamples(withStart: interval.startDate, end: interval.endDate)
            let vals: [Double] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: hrType, predicate: hrPred,
                                       limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    cont.resume(returning: (samples as? [HKQuantitySample])?
                        .map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) } ?? [])
                }
                store.execute(q)
            }
            allHR.append(contentsOf: vals)
        }
        let avgHR: Double? = allHR.isEmpty ? nil : (allHR.reduce(0, +) / Double(allHR.count)).rounded()

        // HRV within sleep window
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let hrvSamples = await allSamples(type: hrvType, from: prevEvening, to: morning, unit: .secondUnit(with: .milli))
        let avgHRV: Double? = hrvSamples.isEmpty ? nil : (hrvSamples.reduce(0, +) / Double(hrvSamples.count)).rounded()

        return SleepResult(totalHours: total, deepHours: deep, remHours: rem, coreHours: core,
                            avgHR: avgHR, avgHRV: avgHRV)
    }

    func weeklySleepHours(from weekStart: Date, to weekEnd: Date) async -> [Double] {
        let cal = Calendar.current
        var results: [Double] = []
        var day = weekStart
        while day <= weekEnd {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if let r = await sleepResult(nightBefore: next) { results.append(r.totalHours) }
            day = next
        }
        return results
    }

    // MARK: - Smart lookups (fallback to adjacent days)

    func hrvOrYesterday(for date: Date) async -> Double? {
        if let v = await hrv(for: date) { return v }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return await hrv(for: yesterday)
    }

    func spO2OrYesterday(for date: Date) async -> Double? {
        if let v = await spO2Percent(for: date) { return v }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return await spO2Percent(for: yesterday)
    }

    func restingHROrYesterday(for date: Date) async -> Double? {
        if let v = await restingHR(for: date) { return v }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return await restingHR(for: yesterday)
    }

    // MARK: - Private helpers

    private func dayRange(for date: Date) -> (Date, Date) {
        let start = Calendar.current.startOfDay(for: date)
        return (start, start.addingTimeInterval(86400))
    }

    private func hkActivityType(for sport: String) -> HKWorkoutActivityType {
        switch sport {
        case "run", "run_indoor":   return .running
        case "bike", "bike_indoor": return .cycling
        case "swim":                return .swimming
        case "strength":            return .traditionalStrengthTraining
        case "core":                return .coreTraining
        case "mobility", "stretch": return .flexibility
        default:                    return .other
        }
    }

    private func distanceType(for sport: String) -> HKQuantityType? {
        switch sport {
        case "run", "run_indoor": return HKQuantityType(.distanceWalkingRunning)
        case "bike", "bike_indoor": return HKQuantityType(.distanceCycling)
        case "swim": return HKQuantityType(.distanceSwimming)
        default: return nil
        }
    }

    private func hrStats(from start: Date, to end: Date) async -> (avg: Int?, max: Int?) {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: pred,
                options: [.discreteAverage, .discreteMax]
            ) { _, stats, _ in
                let unit = HKUnit(from: "count/min")
                let avg = stats?.averageQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
                let max = stats?.maximumQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
                cont.resume(returning: (avg, max))
            }
            store.execute(q)
        }
    }

    private func latestSample(type: HKQuantityType, from start: Date, to end: Date, unit: HKUnit) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func statAverage(type: HKQuantityType, from start: Date, to end: Date, unit: HKUnit) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage
            ) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func statSum(type: HKQuantityType, from start: Date, to end: Date, unit: HKUnit) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func allSamples(type: HKQuantityType, from start: Date, to end: Date, unit: HKUnit) async -> [Double] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let vals = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: unit) } ?? []
                cont.resume(returning: vals)
            }
            store.execute(q)
        }
    }
}
