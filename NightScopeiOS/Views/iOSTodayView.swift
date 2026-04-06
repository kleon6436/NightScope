import SwiftUI

@MainActor
struct iOSTodayViewModel {
    func locationText(_ rawLocationName: String) -> String {
        rawLocationName.isEmpty ? "場所を選択" : rawLocationName
    }

    func navigationTitle(for selectedDate: Date) -> String {
        selectedDate.formatted(.dateTime.year().month().day().weekday())
    }

    func isInitialLoading(isCalculating: Bool, summary: NightSummary?) -> Bool {
        isCalculating && summary == nil
    }

    func refreshAll(using detailViewModel: DetailViewModel) async {
        await detailViewModel.refreshWeather()
        await detailViewModel.refreshLightPollution()
    }

    func triggerRefresh(using detailViewModel: DetailViewModel) {
        Task {
            await refreshAll(using: detailViewModel)
        }
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
    private var weather: DayWeatherSummary? {
        detailViewModel.weatherService.summary(for: detailViewModel.selectedDate)
    }

    private var isInitialLoading: Bool {
        viewModel.isInitialLoading(isCalculating: detailViewModel.isCalculating, summary: nightSummary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    locationDateHeader
                        .padding(.top, Spacing.xs)

                    contentSection
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.sm)
            }
            .refreshable {
                await viewModel.refreshAll(using: detailViewModel)
            }
            .navigationTitle(viewModel.navigationTitle(for: detailViewModel.selectedDate))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarActions
                }
            }
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
        if isInitialLoading {
            loadingPlaceholder
        } else if let summary = nightSummary {
            mainContent(summary: summary)
        }
    }

    private var toolbarActions: some View {
        HStack(spacing: Spacing.xs) {
            Button { showCalendar = true } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("日付を選択")

            Button {
                viewModel.triggerRefresh(using: detailViewModel)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("データを更新")
        }
    }

    private var locationDateHeader: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: AppIcons.Navigation.locationPin)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(viewModel.locationText(detailViewModel.locationName))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(Array(IOSDesignTokens.Today.loadingCardHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(.quaternary)
                    .frame(height: height)
            }
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private func mainContent(summary: NightSummary) -> some View {
        if let index = starGazingIndex {
            StarGazingIndexCard(
                index: index,
                lightPollutionViewModel: lightPollutionViewModel
            )
        }

        DarkTimeCard(summary: summary, weather: weather)
        NightWeatherCard(weather: weather, viewModel: weatherViewModel)
        MoonPhaseCard(summary: summary)
        ViewingWindowsSection(summary: summary)
            .padding(.top, Spacing.xs)
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
