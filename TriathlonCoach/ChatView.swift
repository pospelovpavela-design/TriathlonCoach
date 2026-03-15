import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: AppStore

    @State private var generatedPrompt: String = ""
    @State private var pastedResponse: String = ""
    @State private var extractedWorkouts: [WorkoutPlanJSON] = []
    @State private var loadedCount: Int? = nil
    @State private var copied = false
    @State private var selectedRequest: PlanRequest = .thisWeek

    enum PlanRequest: String, CaseIterable {
        case thisWeek = "Эта неделя"
        case nextWeek = "Следующая"
        case recovery = "Восстановление"
        case preRace  = "Пред-старт"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                step1Section
                step2Section
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .onAppear { generatePrompt() }
        .onChange(of: store.pendingPrompt) { msg in
            guard !msg.isEmpty else { return }
            generatedPrompt = msg
            pastedResponse = ""
            extractedWorkouts = []
            loadedCount = nil
            store.pendingPrompt = ""
        }
        .onChange(of: selectedRequest) { _ in generatePrompt() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ТРЕНЕР").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)).tracking(4)
                Text("Промт-помощник").font(.system(size: 24, weight: .black)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.top, 16).padding(.bottom, 4)
    }

    // MARK: - Step 1

    private var step1Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel("1", "Выбери запрос и скопируй промт")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlanRequest.allCases, id: \.self) { req in
                        Button(req.rawValue) { selectedRequest = req }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedRequest == req ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedRequest == req ? Color.blue : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 1)
            }

            Text(generatedPrompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))

            Button(action: copyPrompt) {
                HStack {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Скопировано!" : "Скопировать промт")
                }
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(copied ? Color.green.opacity(0.85) : Color.blue.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.circle").foregroundColor(.white.opacity(0.3))
                Text("Открой claude.ai, вставь промт, получи ответ")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
            }
        }
    }

    // MARK: - Step 2

    private var step2Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepLabel("2", "Вставь ответ от Claude")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedResponse)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 130, maxHeight: 260)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
                    .onChange(of: pastedResponse, perform: parseResponse)

                if pastedResponse.isEmpty {
                    Text("Вставь ответ Claude с JSON-планом...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.22))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            if !extractedWorkouts.isEmpty {
                loadBanner
            }
        }
    }

    private var loadBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 20)).foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Найдено \(extractedWorkouts.count) тренировок")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                if let n = loadedCount {
                    Text("✓ Загружено в план: \(n)")
                        .font(.system(size: 12)).foregroundColor(.green)
                } else {
                    Text("Нажми чтобы добавить в план")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            if loadedCount == nil {
                Button(action: loadPlan) {
                    Text("Загрузить")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.green).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func stepLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .black)).foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
        }
    }

    // MARK: - Logic

    private func generatePrompt() {
        let weekRange: String
        let requestText: String
        switch selectedRequest {
        case .thisWeek:
            weekRange = store.currentWeekRange()
            requestText = "Составь план тренировок на эту неделю (\(weekRange))."
        case .nextWeek:
            weekRange = store.nextWeekRange()
            requestText = "Составь план тренировок на следующую неделю (\(weekRange))."
        case .recovery:
            weekRange = store.nextWeekRange()
            requestText = "Составь восстановительную неделю (\(weekRange)) — сниженный объём, только Z1–Z2."
        case .preRace:
            weekRange = store.nextWeekRange()
            requestText = "Составь пред-соревновательную неделю (\(weekRange)) — умеренный объём с активацией."
        }
        generatedPrompt = ClaudeService.buildCopyablePrompt(profile: store.profile, requestText: requestText)
        extractedWorkouts = []
        loadedCount = nil
        pastedResponse = ""
    }

    private func copyPrompt() {
        UIPasteboard.general.string = generatedPrompt
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
    }

    private func parseResponse(_ text: String) {
        extractedWorkouts = ClaudeService.shared.extractWorkouts(from: text)
        loadedCount = nil
    }

    private func loadPlan() {
        store.addOrReplace(extractedWorkouts)
        loadedCount = extractedWorkouts.count
    }
}
