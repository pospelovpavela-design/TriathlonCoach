import SwiftUI
import UniformTypeIdentifiers

struct WeekCalendarView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var wkManager: WorkoutKitManager

    @State private var weekOffset = 0
    @State private var selectedWorkout: WorkoutPlanJSON?
    @State private var showDetail = false
    @State private var showFilePicker = false
    @State private var toast: String? = nil

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
    }
    private var weekWorkouts: [WorkoutPlanJSON] { store.workouts(forWeek: referenceDate) }
    private var weekDays: [Date] {
        let (mon, _) = store.weekBounds(containing: referenceDate)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: mon) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                weekNavigator
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(weekDays, id: \.self) { day in
                            DaySection(
                                day: day,
                                workouts: store.workouts(forDay: day),
                                wkManager: wkManager,
                                onTap: { w in selectedWorkout = w; showDetail = true }
                            )
                        }
                        if weekWorkouts.contains(where: { $0.sport != "rest" }) {
                            sendAllButton
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            if let t = toast {
                VStack {
                    Spacer()
                    Text(t).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Color.green.opacity(0.9)).clipShape(Capsule())
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .sheet(isPresented: $showDetail) {
            if let w = selectedWorkout {
                WorkoutDetailView(
                    workout: w,
                    wkManager: wkManager,
                    onUpdate: { updated in store.update(updated) }
                )
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    _ = url.startAccessingSecurityScopedResource()
                    store.loadFromURL(url)
                    url.stopAccessingSecurityScopedResource()
                }
                showToast("Файлы загружены")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("КАЛЕНДАРЬ").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)).tracking(4)
                Text(weekLabel).font(.system(size: 20, weight: .black)).foregroundColor(.white)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { showFilePicker = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(wkManager.authorizationStatus == .authorized ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Image(systemName: "applewatch").font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private var weekNavigator: some View {
        HStack {
            Button(action: { weekOffset -= 1 }) {
                Image(systemName: "chevron.left").foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08)).clipShape(Circle())
            }
            Spacer()
            if weekOffset != 0 {
                Button("Эта неделя") { weekOffset = 0 }
                    .font(.system(size: 13)).foregroundColor(.blue)
            }
            Spacer()
            Button(action: { weekOffset += 1 }) {
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08)).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    private var sendAllButton: some View {
        Button(action: {
            Task {
                let result = await wkManager.saveAllWorkouts(weekWorkouts)
                showToast("На Watch: \(result.saved) тренировок")
            }
        }) {
            HStack {
                Image(systemName: "applewatch")
                Text("Все на Apple Watch").fontWeight(.bold)
            }
            .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(LinearGradient(
                colors: [Color(red: 0.2, green: 0.4, blue: 0.9), Color(red: 0.1, green: 0.3, blue: 0.8)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(wkManager.authorizationStatus != .authorized)
    }

    private var weekLabel: String {
        let (mon, sun) = store.weekBounds(containing: referenceDate)
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "ru_RU")
        return "\(fmt.string(from: mon)) – \(fmt.string(from: sun))"
    }

    private func showToast(_ msg: String) {
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Day Section

struct DaySection: View {
    let day: Date
    let workouts: [WorkoutPlanJSON]
    let wkManager: WorkoutKitManager
    let onTap: (WorkoutPlanJSON) -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var dayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "EEE, d MMM"
        return fmt.string(from: day).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dayLabel)
                    .font(.system(size: 12, weight: isToday ? .bold : .medium))
                    .foregroundColor(isToday ? .blue : .white.opacity(0.4))
                    .tracking(1)
                    .textCase(.uppercase)
                if isToday {
                    Text("СЕГОДНЯ").font(.system(size: 10, weight: .black))
                        .foregroundColor(.blue).tracking(2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if workouts.isEmpty {
                HStack {
                    Image(systemName: "moon.zzz").font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.15))
                    Text("Отдых").font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.15))
                }
                .padding(.horizontal, 16).padding(.bottom, 4)
            } else {
                ForEach(workouts) { workout in
                    WorkoutRow(
                        workout: workout,
                        isSaved: wkManager.isAlreadySaved(workout.title),
                        onSave: { await wkManager.saveWorkout(workout) },
                        onTap: { onTap(workout) }
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 6)
        .background(isToday ? Color.blue.opacity(0.04) : Color.clear)
    }
}
