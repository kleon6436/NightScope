import SwiftUI

@MainActor
struct iOSForecastViewModel {
    private let stateResolver = DetailContentStateResolver()

    func displayState(hasDisplayNights: Bool, isUpcomingLoading: Bool) -> LoadableContentState {
        stateResolver.forecastState(
            hasDisplayNights: hasDisplayNights,
            isUpcomingLoading: isUpcomingLoading
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
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerSection
                contentByState
            }
            .padding(.vertical, Spacing.sm)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var headerSection: some View {
        iOSTabHeaderView(
            title: "14日予報"
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
            EmptyView()
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
        ProgressView("予報を計算中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "予報データがありません",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("14日間の予報データを計算できませんでした")
        )
    }

    private var forecastList: some View {
        List {
            ForEach(gridViewModel.displayNights, id: \.date) { night in
                forecastRow(for: night)
            }
        }
        .listStyle(.plain)
    }

    private func forecastRow(for night: NightSummary) -> some View {
        let index = gridViewModel.starGazingIndex(for: night.date)
        let weather = gridViewModel.weatherSummary(for: night.date)
        let rangeText = gridViewModel.observableRangeText(night: night, weather: weather)

        return iOSNightCardRow(
            night: night,
            index: index,
            weather: weather,
            rangeText: rangeText,
            isSelected: gridViewModel.isDateSelected(night.date)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(IOSDesignTokens.Forecast.rowInsets)
        .onTapGesture {
            viewModel.selectNight(night.date, using: gridViewModel, selectedTab: $selectedTab)
        }
        .accessibilityLabel(gridViewModel.cardAccessibilityLabel(night: night, weather: weather, index: index))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして今夜タブで詳細を表示")
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
