import SwiftUI

struct DetailView: View {
    @ObservedObject var appController: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let summary = appController.nightSummary {
                detailContent(summary: summary)
            } else if appController.isCalculating {
                loadingContent
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NightScope は没入型体験を重視するため、HIG 例外として
        // ウィンドウツールバー背景を一時的に非表示にしている。
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay(alignment: .bottom, content: errorOverlay)
        .animation(reduceMotion ? .none : .standard, value: appController.weatherService.errorMessage)
        .animation(reduceMotion ? .none : .standard, value: appController.lightPollutionService.fetchFailed)
    }

    private func detailContent(summary: NightSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection(summary: summary)
                ViewingWindowsSection(summary: summary)
                UpcomingNightsGrid(appController: appController)
            }
            .padding(Spacing.md)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var loadingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection(summary: .placeholder)
            }
            .padding(Spacing.md)
            .redacted(reason: .placeholder)
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel("星空データを計算中")
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            "データがありません",
            systemImage: AppIcons.Astronomy.moonStars,
            description: Text("場所と日付を選択してください")
        )
    }

    @ViewBuilder
    private func errorOverlay() -> some View {
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
