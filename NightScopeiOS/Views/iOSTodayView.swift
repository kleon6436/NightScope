import SwiftUI

@MainActor
struct iOSTodayViewModel {
    private let stateResolver = DetailContentStateResolver()

    func locationText(_ rawLocationName: String) -> String {
        rawLocationName.isEmpty ? "場所を選択" : rawLocationName
    }

    func headerTitle(for selectedDate: Date) -> String {
        selectedDate.formatted(.dateTime.year().month().day().weekday())
    }

    func contentState(isCalculating: Bool, summary: NightSummary?) -> LoadableContentState {
        stateResolver.todayState(isCalculating: isCalculating, summary: summary)
    }

    func refreshAll(using detailViewModel: DetailViewModel) async {
        await detailViewModel.refreshWeather()
        await detailViewModel.refreshLightPollution()
    }
}

struct iOSTodayView: View {
    @ObservedObject var detailViewModel: DetailViewModel
    private let viewModel = iOSTodayViewModel()
    @StateObject private var lightPollutionViewModel: StarGazingIndexCardViewModel
    @StateObject private var weatherViewModel = NightWeatherCardViewModel()
    @State private var showCalendar = false

    init(detailViewModel: DetailViewModel) {
        self.detailViewModel = detailViewModel
        _lightPollutionViewModel = StateObject(
            wrappedValue: StarGazingIndexCardViewModel(
                lightPollutionService: detailViewModel.lightPollutionService
            )
        )
    }

    private var nightSummary: NightSummary? { detailViewModel.nightSummary }
    private var starGazingIndex: StarGazingIndex? { detailViewModel.starGazingIndex }
    private var weather: DayWeatherSummary? { detailViewModel.currentWeather }

    private var contentState: LoadableContentState {
        viewModel.contentState(isCalculating: detailViewModel.isCalculating, summary: nightSummary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    headerSection
                    contentSection
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
            }
            .refreshable {
                await viewModel.refreshAll(using: detailViewModel)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCalendar) {
                NavigationStack {
                    CalendarView(selectedDate: $detailViewModel.selectedDate)
                        .navigationTitle("日付を選択")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完了") { showCalendar = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var contentSection: some View {
        switch contentState {
        case .loading:
            loadingPlaceholder
        case .empty:
            emptyStateView
        case .content:
            if let summary = nightSummary {
                mainContent(summary: summary)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "今夜の観測データがありません",
            systemImage: "moon.zzz",
            description: Text("場所や日付を変更して再度お試しください")
        )
    }

    @ViewBuilder
    private func mainContent(summary: NightSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let index = starGazingIndex {
                StarGazingIndexCard(
                    index: index,
                    lightPollutionViewModel: lightPollutionViewModel
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DarkTimeCard(summary: summary, weather: weather)
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight)

            NightWeatherCard(weather: weather, isLoading: detailViewModel.isWeatherLoading, viewModel: weatherViewModel)
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight)

            MoonPhaseCard(summary: summary)
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight)

            MilkyWaySummaryCard(summary: summary)
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight, alignment: .top)
                .padding(.top, Spacing.xs)
        }
    }

    private var headerSection: some View {
        iOSTabHeaderView(
            title: viewModel.headerTitle(for: detailViewModel.selectedDate)
        ) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Navigation.locationPin)
                    .font(.subheadline)
                Text(viewModel.locationText(detailViewModel.locationName))
                    .font(.subheadline)
                    .lineLimit(1)
            }
        } trailing: {
            Button {
                showCalendar = true
            } label: {
                Image(systemName: "calendar")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("日付を選択")
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(Array(IOSDesignTokens.Today.loadingCardHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .redacted(reason: .placeholder)
    }

}

#Preview("Today - Loading") {
    iOSTodayView(detailViewModel: IOSPreviewFactory.detailViewModel(for: .loading))
}

#Preview("Today - Empty") {
    iOSTodayView(detailViewModel: IOSPreviewFactory.detailViewModel(for: .empty))
}

#Preview("Today - Content") {
    iOSTodayView(detailViewModel: IOSPreviewFactory.detailViewModel(for: .content))
}
