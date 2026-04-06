import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    @ObservedObject var assistantViewModel: AssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var starGazingIndexCardViewModel: StarGazingIndexCardViewModel
    @StateObject private var nightWeatherCardViewModel: NightWeatherCardViewModel
    @StateObject private var upcomingGridViewModel: UpcomingNightsGridViewModel

    init(viewModel: DetailViewModel, assistantViewModel: AssistantViewModel) {
        self.viewModel = viewModel
        self.assistantViewModel = assistantViewModel
        _starGazingIndexCardViewModel = StateObject(wrappedValue: StarGazingIndexCardViewModel(lightPollutionService: viewModel.lightPollutionService))
        _nightWeatherCardViewModel = StateObject(wrappedValue: NightWeatherCardViewModel())
        _upcomingGridViewModel = StateObject(wrappedValue: UpcomingNightsGridViewModel(detailViewModel: viewModel))
    }

    var body: some View {
        Group {
            if let summary = viewModel.nightSummary {
                detailContent(summary: summary)
            } else if viewModel.isCalculating {
                loadingContent
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay(alignment: .bottom, content: errorOverlay)
        .animation(reduceMotion ? .none : .standard, value: viewModel.hasWeatherError)
        .animation(reduceMotion ? .none : .standard, value: viewModel.hasLightPollutionError)
    }

    private func detailContent(summary: NightSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection(summary: summary)
                ViewingWindowsSection(summary: summary)
                AssistantCard(viewModel: assistantViewModel)
                UpcomingNightsGrid(viewModel: upcomingGridViewModel)
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
            if viewModel.hasLightPollutionError {
                errorBanner(
                    message: "光害データの取得に失敗しました",
                    retryAction: { Task { await viewModel.refreshLightPollution() } }
                )
            }
            if let error = viewModel.weatherErrorMessage {
                errorBanner(
                    message: error,
                    retryAction: { Task { await viewModel.refreshWeather() } }
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
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
        .shadow(radius: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("エラー: \(message)")
    }

    // MARK: - Header

    private func headerSection(summary: NightSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                Text(viewModel.locationName)
                    .font(.largeTitle.bold())
                Text(summary.date, style: .date)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let index = viewModel.starGazingIndex {
                Divider()
                Text("星空観測情報")
                    .font(.title3.bold())
                StarGazingIndexCard(index: index, lightPollutionViewModel: starGazingIndexCardViewModel)
            }

            GlassEffectContainer {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    DarkTimeCard(
                        summary: summary,
                        weather: viewModel.weatherService.summary(for: viewModel.selectedDate)
                    )
                    NightWeatherCard(
                        weather: viewModel.weatherService.summary(for: viewModel.selectedDate),
                        viewModel: nightWeatherCardViewModel
                    )
                    MoonPhaseCard(summary: summary)
                }
            }
        }
    }
}
