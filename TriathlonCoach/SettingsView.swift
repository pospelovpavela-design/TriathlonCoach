import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    @State private var profile: AthleteProfile = AthleteProfile()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                profileSection
                zonesSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea())
        .onAppear {
            profile = store.profile
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ПРОФИЛЬ").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)).tracking(4)
                Text("Настройки").font(.system(size: 28, weight: .black)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.top, 16).padding(.bottom, 4)
    }

    // MARK: - Profile section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Профиль атлета")
            VStack(spacing: 12) {
                fieldRow("Имя", value: $profile.name)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Макс. пульс").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                        TextField("185", value: $profile.maxHR, format: .number)
                            .foregroundColor(.white).keyboardType(.numberPad)
                            .padding(12).background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Пульс покоя").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                        TextField("55", value: $profile.restingHR, format: .number)
                            .foregroundColor(.white).keyboardType(.numberPad)
                            .padding(12).background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("О себе (цели, уровень, особенности)")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                    TextField("Триатлон, цель — полужелезная дистанция...",
                              text: $profile.notes, axis: .vertical)
                        .lineLimit(4).foregroundColor(.white)
                        .padding(12).background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: { store.saveProfile(profile) }) {
                    Text("Сохранить профиль").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white).frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(14).background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Zones section

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Пульсовые зоны")
            VStack(spacing: 8) {
                zoneRow("Z1", "до 119", "Восстановление", Color(red: 0.13, green: 0.77, blue: 0.37))
                zoneRow("Z2", "120–145", "Аэробная база", Color(red: 0.23, green: 0.51, blue: 0.96))
                zoneRow("Z3", "146–163", "Аэробный порог", Color(red: 0.92, green: 0.70, blue: 0.03))
                zoneRow("Z4", "164–175", "Анаэробный порог", Color(red: 0.98, green: 0.45, blue: 0.09))
                zoneRow("Z5", "176+", "Максимум", Color(red: 0.94, green: 0.27, blue: 0.27))
            }
            .padding(14).background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func fieldRow(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            TextField(label, text: value)
                .foregroundColor(.white).padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.4)).tracking(3)
    }

    private func zoneRow(_ zone: String, _ range: String, _ name: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(zone).font(.system(size: 14, weight: .bold)).foregroundColor(color)
            }.frame(width: 34, alignment: .leading)
            Text("\(range) уд/мин").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                .frame(width: 110, alignment: .leading)
            Text(name).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
            Spacer()
        }
    }
}
