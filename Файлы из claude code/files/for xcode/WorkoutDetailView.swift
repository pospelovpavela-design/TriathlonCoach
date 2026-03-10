import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutPlanJSON
    @ObservedObject var wkManager: WorkoutKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveResult: String?

    private var totalMinutes: Int { workout.intervals.reduce(0) { $0 + $1.duration_min } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Hero
                        heroSection

                        // Intervals
                        intervalsSection

                        // Description
                        if !workout.description.isEmpty {
                            descriptionSection
                        }

                        // Send to Watch
                        if workout.sport != "rest" && workout.sport != "mobility" {
                            watchSection
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(workout.formattedDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(3)
                    .textCase(.uppercase)
                Spacer()
                if workout.isToday {
                    Text("СЕГОДНЯ")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(zoneSwiftUIColor(workout.target_zone))
                        .tracking(2)
                }
            }

            Text(workout.title)
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                statPill(icon: "clock", value: "\(workout.duration_min) мин")
                statPill(icon: "chart.bar", value: "\(workout.intervals.count) отрезков")
                if let rpe = workout.rpe_target {
                    statPill(icon: "bolt", value: "RPE \(rpe)/10")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
    }

    // MARK: - Intervals

    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ОТРЕЗКИ")

            // Visual timeline bar
            timelineBar

            // Interval rows
            ForEach(Array(workout.intervals.enumerated()), id: \.element.id) { idx, interval in
                IntervalDetailRow(interval: interval, index: idx + 1, totalIntervals: workout.intervals.count)
            }
        }
    }

    private var timelineBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(workout.intervals) { interval in
                    let fraction = CGFloat(interval.duration_min) / CGFloat(totalMinutes)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(zoneSwiftUIColor(interval.zone))
                        .frame(width: max((geo.size.width - CGFloat(workout.intervals.count - 1) * 2) * fraction, 10))
                }
            }
        }
        .frame(height: 10)
        .padding(.bottom, 4)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ОПИСАНИЕ")
            Text(workout.description)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Watch Section

    private var watchSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    isSaving = true
                    let success = await wkManager.saveWorkout(workout)
                    isSaving = false
                    saveResult = success
                        ? "✓ Тренировка добавлена на Apple Watch!\nОткрой приложение Тренировка на часах."
                        : (wkManager.lastError ?? "Ошибка")
                }
            }) {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else if wkManager.isAlreadySaved(workout.title) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Уже на Apple Watch")
                    } else {
                        Image(systemName: "applewatch")
                        Text("Добавить на Apple Watch")
                    }
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    wkManager.isAlreadySaved(workout.title)
                        ? LinearGradient(colors: [.green.opacity(0.8), .green.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(
                            colors: [Color(red: 0.2, green: 0.4, blue: 0.9), Color(red: 0.1, green: 0.3, blue: 0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isSaving)

            if let result = saveResult {
                Text(result)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            // How it works on Watch
            watchInfoCard
        }
    }

    private var watchInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Как это работает на часах", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            Text("Тренировка появится в приложении Тренировка → Собственная тренировка. Часы покажут каждый отрезок, целевой пульс и будут вибрировать при выходе из зоны.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(3)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white.opacity(0.3))
            .tracking(3)
    }
}

// MARK: - Interval Detail Row

struct IntervalDetailRow: View {
    let interval: IntervalJSON
    let index: Int
    let totalIntervals: Int

    private var zoneColor: Color { zoneSwiftUIColor(interval.zone) }
    private var zone: HRZone? { HRZone.zone(for: interval.zone) }

    var body: some View {
        HStack(spacing: 12) {
            // Timeline dot + line
            VStack(spacing: 0) {
                Circle()
                    .fill(zoneColor)
                    .frame(width: 10, height: 10)
                if index < totalIntervals {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(interval.note)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(interval.duration_min) мин")
                        .font(.system(size: 14, weight: .mono))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                }

                HStack(spacing: 6) {
                    Text(interval.zone)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(zoneColor)
                    if let z = zone {
                        Text("·")
                            .foregroundColor(.white.opacity(0.2))
                        Text(z.displayRange)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                        Text("·")
                            .foregroundColor(.white.opacity(0.2))
                        Text(z.name)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(zoneColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(zoneColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
