import SwiftUI

@MainActor
struct iOSForecastRowModel {
    let night: NightSummary
    let index: StarGazingIndex?
    let weather: DayWeatherSummary?
    let rangeText: String
    let isReliableWeather: Bool
    let hasPartialWeather: Bool
    let isForecastOutOfRange: Bool
    let hasWeatherLoadError: Bool
    let isSelected: Bool
    let accessibilityLabel: String
}

@MainActor
struct iOSForecastViewModel {
    private let stateResolver = DetailContentStateResolver()

    func displayState(hasDisplayNights: Bool, isUpcomingLoading: Bool) -> LoadableContentState {
        stateResolver.forecastState(
            hasDisplayNights: hasDisplayNights,
            isUpcomingLoading: isUpcomingLoading
        )
    }

    func rowModel(for night: NightSummary, using gridViewModel: UpcomingNightsGridViewModel) -> iOSForecastRowModel {
        let index = gridViewModel.starGazingIndex(for: night.date)
        let weather = gridViewModel.weatherSummary(for: night.date)
        let rangeText = gridViewModel.observableRangeText(night: night, weather: weather)
        let isReliableWeather = gridViewModel.hasReliableWeatherData(for: night, weather: weather)
        let hasPartialWeather = gridViewModel.hasPartialWeatherData(for: night, weather: weather)
        let isForecastOutOfRange = gridViewModel.isForecastOutOfRange(for: night, weather: weather)

        return iOSForecastRowModel(
            night: night,
            index: index,
            weather: weather,
            rangeText: rangeText,
            isReliableWeather: isReliableWeather,
            hasPartialWeather: hasPartialWeather,
            isForecastOutOfRange: isForecastOutOfRange,
            hasWeatherLoadError: gridViewModel.weatherErrorMessage != nil,
            isSelected: gridViewModel.isDateSelected(night.date),
            accessibilityLabel: gridViewModel.cardAccessibilityLabel(night: night, weather: weather, index: index)
        )
    }

    func selectNight(_ date: Date, using gridViewModel: UpcomingNightsGridViewModel, selectedTab: Binding<Int>) {
        gridViewModel.setSelectedDate(date)
        selectedTab.wrappedValue = 0
    }
}

struct iOSForecastView: View {
    @ObservedObject var detailViewModel: DetailViewModel
    @Binding var selectedTab: Int
    private let viewModel = iOSForecastViewModel()
    @StateObject private var gridViewModel: UpcomingNightsGridViewModel

    init(detailViewModel: DetailViewModel, selectedTab: Binding<Int>) {
        self.detailViewModel = detailViewModel
        self._selectedTab = selectedTab
        self._gridViewModel = StateObject(wrappedValue: UpcomingNightsGridViewModel(detailViewModel: detailViewModel))
    }

    private var displayState: LoadableContentState {
        viewModel.displayState(
            hasDisplayNights: !gridViewModel.displayNights.isEmpty,
            isUpcomingLoading: detailViewModel.isUpcomingLoading || gridViewModel.isLoading
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    headerSection
                    contentByState
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
            }
            .refreshable {
                await detailViewModel.refreshWeather()
                await detailViewModel.refreshForecast()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var headerSection: some View {
        iOSTabHeaderView(
            title: "14日予報",
            horizontalPadding: Spacing.xs
        ) {
            VStack(alignment: .leading, spacing: Spacing.xs / 2) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: AppIcons.Navigation.locationPin)
                        .font(.subheadline)
                    Text(detailViewModel.locationName.isEmpty ? "場所を選択" : detailViewModel.locationName)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                Text("今後14日間の夜空の見通し")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        } trailing: {
            if detailViewModel.isUpcomingLoading || gridViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("14日予報を更新中")
            }
        }
    }

    @ViewBuilder
    private var contentByState: some View {
        switch displayState {
        case .loading:
            loadingView
        case .empty:
            emptyStateView
        case .content:
            forecastList
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView()
            Text("予報を計算中...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: IOSDesignTokens.Forecast.loadingMinHeight)
        .iOSMaterialPanel()
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("予報データがありません", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("14日間の予報データを計算できませんでした")
        } actions: {
            Button("再試行") {
                detailViewModel.retryForecastInBackground()
            }
        }
    }

    private var forecastList: some View {
        LazyVStack(alignment: .leading, spacing: IOSDesignTokens.Forecast.rowSpacing) {
            ForEach(gridViewModel.displayNights, id: \.date) { night in
                forecastRow(for: night)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func forecastRow(for night: NightSummary) -> some View {
        let rowModel = viewModel.rowModel(for: night, using: gridViewModel)

        return Button {
            viewModel.selectNight(rowModel.night.date, using: gridViewModel, selectedTab: $selectedTab)
        } label: {
            iOSNightCardRow(
                night: rowModel.night,
                index: rowModel.index,
                weather: rowModel.weather,
                rangeText: rowModel.rangeText,
                isReliableWeather: rowModel.isReliableWeather,
                hasPartialWeather: rowModel.hasPartialWeather,
                isForecastOutOfRange: rowModel.isForecastOutOfRange,
                hasWeatherLoadError: rowModel.hasWeatherLoadError,
                isSelected: rowModel.isSelected
            )
        }
        .buttonStyle(ForecastRowButtonStyle())
        .accessibilityLabel(rowModel.accessibilityLabel)
        .accessibilityHint("タップして今夜タブで詳細を表示")
        .accessibilityAddTraits(rowModel.isSelected ? .isSelected : [])
    }
}

private struct ForecastRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? .none : .spring(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview("Forecast - Loading") {
    iOSForecastView(
        detailViewModel: IOSPreviewFactory.detailViewModel(for: .loading),
        selectedTab: .constant(1)
    )
}

#Preview("Forecast - Empty") {
    iOSForecastView(
        detailViewModel: IOSPreviewFactory.detailViewModel(for: .empty),
        selectedTab: .constant(1)
    )
}

#Preview("Forecast - Content") {
    iOSForecastView(
        detailViewModel: IOSPreviewFactory.detailViewModel(for: .content),
        selectedTab: .constant(1)
    )
}
