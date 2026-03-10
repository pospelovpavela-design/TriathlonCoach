import SwiftUI

struct ContentView: View {
    @StateObject private var loader = WorkoutLoader()
    @StateObject private var wkManager = WorkoutKitManager()
    @State private var showFilePicker = false
    @State private var selectedWorkout: WorkoutPlanJSON?
    @State private var showDetail = false
    @State private var toast: ToastMessage?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(red: 0.04, green: 0.04, blue: 0.06)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    // Auth banner
                    if wkManager.authorizationStatus != .authorized {
                        authBanner
                    }

                    // Workout list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(loader.workouts) { workout in
                                WorkoutRow(
                                    workout: workout,
                                    isSaved: wkManager.isAlreadySaved(workout.title),
                                    onSave: { await saveWorkout(workout) },
                                    onTap: {
                                        selectedWorkout = workout
                                        showDetail = true
                                    }
                                )
                            }

                            // Save all button
                            if !loader.workouts.isEmpty {
                                saveAllButton
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }

                // Toast
                if let t = toast {
                    ToastView(message: t)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(99)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 60)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showDetail) {
                if let w = selectedWorkout {
                    WorkoutDetailView(workout: w, wkManager: wkManager)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }
        .task {
            await wkManager.requestAuthorization()
            await wkManager.loadSavedPlans()
            loader.loadFromDocuments()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TRIATHLON")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(4)
                Text("COACH")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { showFilePicker = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Watch status indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(wkManager.authorizationStatus == .authorized ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Image(systemName: "applewatch")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 16)
    }

    private var authBanner: some View {
        Button(action: {
            Task { await wkManager.requestAuthorization() }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.watchface")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Нужен доступ к Apple Watch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Нажми чтобы разрешить WorkoutKit")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(16)
            .background(Color.orange.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var saveAllButton: some View {
        Button(action: {
            Task {
                let result = await wkManager.saveAllWorkouts(loader.workouts)
                showToast("✓ Добавлено на Watch: \(result.saved) тренировок", style: .success)
            }
        }) {
            HStack {
                if wkManager.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "applewatch")
                    Text("Добавить все на Apple Watch")
                        .fontWeight(.bold)
                        .tracking(1)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.2, green: 0.4, blue: 0.9), Color(red: 0.1, green: 0.3, blue: 0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(wkManager.isLoading || wkManager.authorizationStatus != .authorized)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func saveWorkout(_ workout: WorkoutPlanJSON) async {
        let success = await wkManager.saveWorkout(workout)
        if success {
            showToast("✓ \"\(workout.title)\" добавлена на Watch", style: .success)
        } else {
            showToast(wkManager.lastError ?? "Ошибка сохранения", style: .error)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                loader.loadFromURL(url)
                url.stopAccessingSecurityScopedResource()
            }
            showToast("Файлы загружены", style: .success)
        case .failure(let error):
            showToast("Ошибка: \(error.localizedDescription)", style: .error)
        }
    }

    private func showToast(_ message: String, style: ToastMessage.Style) {
        withAnimation(.spring()) {
            toast = ToastMessage(text: message, style: style)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Toast

struct ToastMessage {
    let text: String
    let style: Style
    enum Style { case success, error, info }
    var color: Color {
        switch style {
        case .success: return .green
        case .error:   return .red
        case .info:    return .blue
        }
    }
}

struct ToastView: View {
    let message: ToastMessage
    var body: some View {
        Text(message.text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(message.color.opacity(0.9))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8)
    }
}
