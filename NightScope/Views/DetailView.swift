import SwiftUI

struct DetailView: View {
    @ObservedObject var appController: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let summary = appController.nightSummary {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        headerSection(summary: summary)
                        ViewingWindowsSection(summary: summary)
                        UpcomingNightsGrid(appController: appController)
                    }
                    .padding(Spacing.md)
                }
                .ignoresSafeArea(edges: .top)
            } else if appController.isCalculating {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        headerSection(summary: .placeholder)
                    }
                    .padding(Spacing.md)
                    .redacted(reason: .placeholder)
                }
                .ignoresSafeArea(edges: .top)
                .accessibilityLabel("星空データを計算中")
            } else {
                ContentUnavailableView(
                    "データがありません",
                    systemImage: AppIcons.Astronomy.moonStars,
                    description: Text("場所と日付を選択してください")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            VStack(spacing: Spacing.xs) {
                if appController.lightPollutionService.fetchFailed {
                    errorBanner(
                        message: "光害データの取得に失敗しました",
                        retryAction: { Task { await appController.refreshLightPollution() } }
                    )
                }
                if let error = appController.weatherService.errorMessage {
                    errorBanner(
                        message: error,
                        retryAction: { Task { await appController.refreshWeather() } }
                    )
                }
            }
            .padding(.bottom, Spacing.sm)
        }
        .animation(reduceMotion ? .none : .standard, value: appController.weatherService.errorMessage)
        .animation(reduceMotion ? .none : .standard, value: appController.lightPollutionService.fetchFailed)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String, retryAction: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: AppIcons.Status.warning)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
            Spacer()
            Button("再試行", action: retryAction)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
        .shadow(radius: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("エラー: \(message)")
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
                    DarkTimeCard(
                        summary: summary,
                        weather: appController.weatherService.summary(for: appController.selectedDate)
                    )
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
