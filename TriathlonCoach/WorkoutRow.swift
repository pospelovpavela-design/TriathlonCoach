import SwiftUI

struct WorkoutRow: View {
    let workout: WorkoutPlanJSON
    let isSaved: Bool
    let onSave: () async -> Void
    let onTap: () -> Void

    private var zone: HRZone? { HRZone.zone(for: workout.target_zone) }
    private var zoneColor: Color { zoneSwiftUIColor(workout.target_zone) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left accent bar
                Rectangle()
                    .fill(zoneColor)
                    .frame(width: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                VStack(alignment: .leading, spacing: 8) {
                    // Date + today badge
                    HStack {
                        Text(workout.formattedDate)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(2)
                            .textCase(.uppercase)
                        if workout.isToday {
                            Text("СЕГОДНЯ")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(zoneColor)
                                .tracking(2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(zoneColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Spacer()
                        // Save to Watch button
                        if workout.sport != "rest" && workout.sport != "mobility" && workout.sport != "stretch" {
                            watchButton
                        }
                    }

                    // Title
                    Text(workout.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Meta row
                    HStack(spacing: 10) {
                        // Zone badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(zoneColor)
                                .frame(width: 6, height: 6)
                            Text(workout.target_zone)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(zoneColor)
                            if let z = zone {
                                Text(z.displayRange)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(zoneColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text("\(workout.duration_min) мин")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))

                        if !workout.intervals.isEmpty {
                            Text("· \(workout.intervals.count) отр.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    // Intervals mini preview
                    if !workout.intervals.isEmpty {
                        intervalsMiniBar
                    }
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .background(
            workout.isToday
                ? Color(red: 0.12, green: 0.16, blue: 0.28)
                : Color(red: 0.1, green: 0.1, blue: 0.14)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    workout.isToday ? zoneColor.opacity(0.3) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
    }

    private var watchButton: some View {
        Button(action: { Task { await onSave() } }) {
            HStack(spacing: 5) {
                Image(systemName: isSaved ? "checkmark" : "applewatch")
                    .font(.system(size: 12, weight: .semibold))
                Text(isSaved ? "На Watch" : "→ Watch")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundColor(isSaved ? .green : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSaved
                    ? Color.green.opacity(0.15)
                    : Color.white.opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        isSaved ? Color.green.opacity(0.4) : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var intervalsMiniBar: some View {
        HStack(spacing: 3) {
            ForEach(workout.intervals) { interval in
                let w = CGFloat(interval.duration_min)
                RoundedRectangle(cornerRadius: 3)
                    .fill(zoneSwiftUIColor(interval.zone).opacity(0.6))
                    .frame(width: max(w * 2.5, 16), height: 6)
            }
        }
    }
}

// MARK: - Zone color helper

func zoneSwiftUIColor(_ zone: String) -> Color {
    switch zone {
    case "Z1": return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "Z2": return Color(red: 0.23, green: 0.51, blue: 0.96)
    case "Z3": return Color(red: 0.92, green: 0.70, blue: 0.03)
    case "Z4": return Color(red: 0.98, green: 0.45, blue: 0.09)
    case "Z5": return Color(red: 0.94, green: 0.27, blue: 0.27)
    default:   return Color.gray
    }
}
