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
            HKCategoryType(.sleepAnalysis)
        ]
        do {
            try await store.requestAuthorization(toShare: Set<HKSampleType>(), read: types)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
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

    // MARK: - SpO2

    /// Average SpO2 for a given calendar day (0–100 %)
    func spO2Percent(for date: Date) async -> Double? {
        let type = HKQuantityType(.oxygenSaturation)
        let (start, end) = dayRange(for: date)
        guard let v = await statAverage(type: type, from: start, to: end, unit: .percent()) else { return nil }
        return (v * 100).rounded()
    }

    /// Average SpO2 over a date range (0–100 %)
    func weeklySpO2Percent(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(.oxygenSaturation)
        guard let v = await statAverage(type: type, from: start, to: end, unit: .percent()) else { return nil }
        return (v * 1000).rounded() / 10   // one decimal
    }

    // MARK: - Resting HR

    /// Apple Health computed resting HR for a given day (уд/мин)
    func restingHR(for date: Date) async -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        let (start, end) = dayRange(for: date)
        return await latestSample(type: type, from: start, to: end, unit: HKUnit(from: "count/min"))?.rounded()
    }

    /// Average resting HR over a date range
    func weeklyRestingHRAverage(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        return await statAverage(type: type, from: start, to: end, unit: HKUnit(from: "count/min"))?.rounded()
    }

    // MARK: - Sleep HR

    /// Average HR during sleep for the night before a given date
    /// Queries HR samples within sleep intervals for accuracy
    func sleepHR(nightBefore date: Date) async -> Double? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let prevEvening = cal.date(byAdding: .hour, value: -18, to: dayStart) else { return nil }
        let morning = dayStart.addingTimeInterval(3600 * 12)

        // 1. Get asleep intervals
        let sleepType = HKCategoryType(.sleepAnalysis)
        let sleepPred = HKQuery.predicateForSamples(withStart: prevEvening, end: morning)
        let sleepSamples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: sleepPred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            self.store.execute(q)
        }
        let asleep = sleepSamples.filter { [1, 3, 4, 5, 6].contains($0.value) }
        guard !asleep.isEmpty else { return nil }

        // 2. Collect HR samples from each sleep interval
        let hrType = HKQuantityType(.heartRate)
        var allHR: [Double] = []
        for interval in asleep {
            let pred = HKQuery.predicateForSamples(withStart: interval.startDate, end: interval.endDate)
            let vals: [Double] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: hrType, predicate: pred,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    cont.resume(returning: (samples as? [HKQuantitySample])?
                        .map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) } ?? [])
                }
                self.store.execute(q)
            }
            allHR.append(contentsOf: vals)
        }
        guard !allHR.isEmpty else { return nil }
        return (allHR.reduce(0, +) / Double(allHR.count)).rounded()
    }

    /// Average sleep HR over a date range (from stored per-workout values — no extra query needed)

    // MARK: - Sleep

    struct SleepResult {
        let totalHours: Double
        let deepHours: Double
        let remHours: Double

        var summary: String {
            var p = [String(format: "%.1fч", totalHours)]
            if deepHours > 0 { p.append(String(format: "глуб. %.1fч", deepHours)) }
            if remHours  > 0 { p.append(String(format: "REM %.1fч",  remHours))  }
            return p.joined(separator: ", ")
        }
    }

    /// Sleep from 18:00 the previous day to 12:00 of the given date
    func sleepResult(nightBefore date: Date) async -> SleepResult? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let prevEvening = cal.date(byAdding: .hour, value: -18, to: dayStart) else { return nil }
        let morning = dayStart.addingTimeInterval(3600 * 12)

        let type = HKCategoryType(.sleepAnalysis)
        let pred = HKQuery.predicateForSamples(withStart: prevEvening, end: morning)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: nil); return
                }
                // rawValue: 1=asleep(legacy), 3=asleepCore, 4=asleepDeep, 5=asleepREM, 6=asleepUnspecified
                var total = 0.0, deep = 0.0, rem = 0.0
                for s in samples {
                    guard [1, 3, 4, 5, 6].contains(s.value) else { continue }
                    let h = s.endDate.timeIntervalSince(s.startDate) / 3600
                    total += h
                    if s.value == 4 { deep += h }
                    if s.value == 5 { rem  += h }
                }
                guard total > 0 else { cont.resume(returning: nil); return }
                cont.resume(returning: SleepResult(totalHours: total, deepHours: deep, remHours: rem))
            }
            self.store.execute(q)
        }
    }

    /// Sleep hours per day for a week
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

    // MARK: - Private helpers

    private func dayRange(for date: Date) -> (Date, Date) {
        let start = Calendar.current.startOfDay(for: date)
        return (start, start.addingTimeInterval(86400))
    }

    private func latestSample(type: HKQuantityType, from start: Date, to end: Date, unit: HKUnit) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            self.store.execute(q)
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
            self.store.execute(q)
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
            self.store.execute(q)
        }
    }
}
