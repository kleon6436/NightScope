import SwiftUI

@MainActor
struct iOSForecastViewModel {
    enum DisplayState {
        case loading
        case empty
        case content
    }

    func displayState(hasDisplayNights: Bool, isCalculating: Bool) -> DisplayState {
        if !hasDisplayNights && isCalculating {
            return .loading
        }
        if !hasDisplayNights {
            return .empty
        }
        return .content
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

    private var displayState: iOSForecastViewModel.DisplayState {
        viewModel.displayState(
            hasDisplayNights: !gridViewModel.displayNights.isEmpty,
            isCalculating: detailViewModel.isCalculating
        )
    }

    var body: some View {
        NavigationStack {
            contentByState
            .navigationTitle("14日予報")
            .navigationBarTitleDisplayMode(.large)
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
            isSelected: Calendar.current.isDate(night.date, inSameDayAs: gridViewModel.selectedDate)
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
