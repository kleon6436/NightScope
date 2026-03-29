import SwiftUI

struct DetailView: View {
    @ObservedObject var appController: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if appController.isCalculating {
                VStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("計算中...")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("星空データを計算中")
            } else if let summary = appController.nightSummary {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        headerSection(summary: summary)
                        ViewingWindowsSection(summary: summary)
                        UpcomingNightsGrid(appController: appController)
                    }
                    .padding(Spacing.md)
                }
                .ignoresSafeArea(edges: .top)
            } else {
                ContentUnavailableView(
                    "データがありません",
                    systemImage: "moon.stars",
                    description: Text("場所と日付を選択してください")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            if let error = appController.weatherService.errorMessage {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.body)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
                .shadow(radius: 4)
                .padding(.bottom, Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("エラー: \(error)")
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(reduceMotion ? .none : .standard, value: appController.weatherService.errorMessage)
    }

    // MARK: - Header

    private func headerSection(summary: NightSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                Text(appController.locationController.locationName)
                    .font(.largeTitle.bold())
                Text(summary.date, style: .date)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let index = appController.starGazingIndex {
                Divider()
                Text("星空観測情報")
                    .font(.title3.bold())
                StarGazingIndexCard(index: index, lightPollutionService: appController.lightPollutionService)
            }

            GlassEffectContainer {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    DarkTimeCard(summary: summary)
                    NightWeatherCard(
                        weather: appController.weatherService.summary(for: appController.selectedDate),
                        isLoading: appController.weatherService.isLoading
                    )
                    MoonPhaseCard(summary: summary)
                }
            }
        }
    }
}
