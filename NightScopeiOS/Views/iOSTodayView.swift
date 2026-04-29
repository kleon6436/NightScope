import SwiftUI

@MainActor
/// 今日タブの表示状態と補助処理をまとめる。
struct iOSTodayViewModel {
    private let stateResolver = DetailContentStateResolver()

    func locationText(_ rawLocationName: String) -> String {
        rawLocationName.isEmpty ? "場所を選択" : rawLocationName
    }

    func headerTitle(for selectedDate: Date, timeZone: TimeZone) -> String {
        DateFormatters.yearMonthDayWeekdayStringWithoutWeekday(from: selectedDate, timeZone: timeZone)
    }

    func contentState(isCalculating: Bool, summary: NightSummary?) -> LoadableContentState {
        stateResolver.todayState(isCalculating: isCalculating, summary: summary)
    }

    func refreshAll(using detailViewModel: DetailViewModel) async {
        await detailViewModel.refreshExternalData()
    }
}

/// 今夜の観測サマリーを表示するメイン画面。
struct iOSTodayView: View {
    @ObservedObject var detailViewModel: DetailViewModel
    @ObservedObject var observationModePreference: ObservationModePreference
    private let viewModel = iOSTodayViewModel()
    @StateObject private var lightPollutionViewModel: StarGazingIndexCardViewModel
    @StateObject private var weatherViewModel = NightWeatherCardViewModel()
    @State private var presentedSheet: PresentedSheet?
    @State private var calendarDraftDate = Date()

    /// 詳細画面の ViewModel と観測モード設定を受け取る。
    init(
        detailViewModel: DetailViewModel,
        observationModePreference: ObservationModePreference = ObservationModePreference()
    ) {
        self.detailViewModel = detailViewModel
        self.observationModePreference = observationModePreference
        _lightPollutionViewModel = StateObject(
            wrappedValue: StarGazingIndexCardViewModel(
                lightPollutionService: detailViewModel.lightPollutionService
            )
        )
    }

    private var nightSummary: NightSummary? { detailViewModel.nightSummary }
    private var starGazingIndex: StarGazingIndex? { detailViewModel.displayedStarGazingIndex }
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
            .sheet(item: $presentedSheet) { sheet in
                sheetView(for: sheet)
            }
            .safeAreaInset(edge: .bottom) {
                // エラー表示を常設するため、下端の安全領域にオーバーレイを差し込む。
                DetailErrorOverlay(
                    weatherErrorMessage: detailViewModel.weatherErrorMessage,
                    hasLightPollutionError: detailViewModel.hasLightPollutionError,
                    retryWeatherAction: detailViewModel.retryWeatherInBackground,
                    retryLightPollutionAction: detailViewModel.retryLightPollutionInBackground
                )
            }
        }
    }

    // MARK: - サブビュー

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

            NightWeatherCard(
                weather: weather,
                isLoading: detailViewModel.isWeatherLoading,
                isForecastOutOfRange: detailViewModel.isCurrentWeatherForecastOutOfRange,
                isCoverageIncomplete: detailViewModel.isCurrentWeatherCoverageIncomplete,
                errorMessage: weather == nil ? detailViewModel.weatherErrorMessage : nil,
                viewModel: weatherViewModel
            )
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight)

            MoonPhaseCard(summary: summary)
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight)

            MilkyWaySummaryCard(summary: summary)
                .frame(minHeight: IOSDesignTokens.Today.summaryCardMinHeight, alignment: .top)

            if weather != nil {
                WeatherAttributionBadge()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var headerSection: some View {
        iOSTabHeaderView(
            title: viewModel.headerTitle(
                for: detailViewModel.displayedDate,
                timeZone: detailViewModel.selectedTimeZone
            ),
            titleLineLimit: 1,
            titleMinimumScaleFactor: 0.9,
            horizontalPadding: Spacing.xs
        ) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: AppIcons.Navigation.locationPin)
                        .font(.subheadline)
                    Text(viewModel.locationText(detailViewModel.locationName))
                        .font(.subheadline)
                        .lineLimit(1)
                }

                Button {
                    presentedSheet = .observationMode
                } label: {
                    Label(L10n.tr(observationModePreference.mode.shortTitleKey), systemImage: observationModePreference.mode.iconSystemName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("observation.mode.change"))
                .accessibilityHint(L10n.tr(observationModePreference.mode.descriptionKey))
            }
        } trailing: {
            HStack(spacing: Spacing.xs / 2) {
                Button {
                    calendarDraftDate = detailViewModel.selectedDate
                    presentedSheet = .calendar
                } label: {
                    Image(systemName: "calendar")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .glassButtonStyle()
                .accessibilityLabel(L10n.tr("日付を選択"))

                settingsButton
            }
        }
    }

    private var settingsButton: some View {
        Button {
            presentedSheet = .settings
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .glassButtonStyle()
        .accessibilityLabel(L10n.tr("設定を開く"))
        .accessibilityHint(L10n.tr("アプリ全体の表示設定を変更します"))
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

    @ViewBuilder
    private func sheetView(for sheet: PresentedSheet) -> some View {
        switch sheet {
        case .calendar:
            NavigationStack {
                CalendarView(
                    selectedDate: $calendarDraftDate,
                    timeZone: detailViewModel.selectedTimeZone
                )
                .navigationTitle("日付を選択")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            detailViewModel.selectedDate = calendarDraftDate
                            presentedSheet = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        case .observationMode:
            NavigationStack {
                iOSObservationModeSelectionView(observationModePreference: observationModePreference)
            }
            .presentationDetents([.medium])
        case .settings:
            iOSSettingsSheetView()
        }
    }
}

private extension iOSTodayView {
    /// sheet の種類を識別する。
    enum PresentedSheet: String, Identifiable {
        case calendar
        case observationMode
        case settings

        var id: String { rawValue }
    }
}

/// 観測モードの選択を行う sheet。
private struct iOSObservationModeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var observationModePreference: ObservationModePreference

    var body: some View {
        List {
            ForEach(ObservationMode.allCases) { mode in
                Button {
                    observationModePreference.mode = mode
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: Spacing.xs) {
                            Label(L10n.tr(mode.titleKey), systemImage: mode.iconSystemName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if observationModePreference.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(L10n.tr(mode.descriptionKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(L10n.tr("observation.mode.sectionTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 設定画面を表示する sheet。
private struct iOSSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            dismiss()
                        }
                    }
                }
        }
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
