import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var starGazingIndexCardViewModel: StarGazingIndexCardViewModel
    @StateObject private var nightWeatherCardViewModel: NightWeatherCardViewModel
    @StateObject private var upcomingGridViewModel: UpcomingNightsGridViewModel
    @ObservedObject var starMapViewModel: StarMapViewModel

    init(viewModel: DetailViewModel, starMapViewModel: StarMapViewModel) {
        self.viewModel = viewModel
        self.starMapViewModel = starMapViewModel
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
        // NightScope は没入型体験を重視するため、HIG 例外として
        // ウィンドウツールバー背景を一時的に非表示にしている。
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $starMapViewModel.isStarMapOpen) {
            MacStarMapSheet(viewModel: starMapViewModel)
        }
        .onChange(of: starMapViewModel.isStarMapOpen) { _, isOpen in
            if isOpen {
                starMapViewModel.prepareForStarMapPresentation()
                starMapViewModel.syncWithSelectedDate()
            }
        }
        .overlay(alignment: .bottom) {
            DetailErrorOverlay(
                weatherErrorMessage: viewModel.weatherErrorMessage,
                hasLightPollutionError: viewModel.hasLightPollutionError,
                retryWeatherAction: viewModel.retryWeatherInBackground,
                retryLightPollutionAction: viewModel.retryLightPollutionInBackground
            )
        }
        .animation(reduceMotion ? .none : .standard, value: viewModel.hasWeatherError)
        .animation(reduceMotion ? .none : .standard, value: viewModel.hasLightPollutionError)
    }

    private func detailContent(summary: NightSummary) -> some View {
        let weather = viewModel.currentWeather
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerSection(
                    summary: summary,
                    weather: weather,
                    isWeatherLoading: viewModel.isWeatherLoading,
                    isSummaryRefreshing: viewModel.isCalculating
                )
                UpcomingNightsGrid(viewModel: upcomingGridViewModel)
            }
            .padding(Spacing.md)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var loadingContent: some View {
        let weather = viewModel.currentWeather
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection(
                    summary: .placeholder,
                    weather: weather,
                    isWeatherLoading: viewModel.isWeatherLoading,
                    isSummaryRefreshing: true
                )
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

    // MARK: - Header

    private func headerSection(
        summary: NightSummary,
        weather: DayWeatherSummary?,
        isWeatherLoading: Bool,
        isSummaryRefreshing: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                Text(viewModel.locationName)
                    .font(.largeTitle.bold())
                Text(
                    DateFormatters.yearMonthDayWeekdayString(
                        from: viewModel.displayedDate,
                        timeZone: viewModel.selectedTimeZone
                    )
                )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if isSummaryRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("右側の情報を更新中")
                }
                Spacer()
            }

            if let index = viewModel.starGazingIndex {
                Divider()
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Text("星空観測情報")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        starMapViewModel.isStarMapOpen = true
                    } label: {
                        Label("星空マップ", systemImage: AppIcons.Astronomy.sparkles)
                    }
                    .buttonStyle(.glass)
                    .help("星空マップを表示")
                    .accessibilityHint("選択した日付の星空マップを開きます")
                }
                MacStarGazingIndexCard(index: index, lightPollutionViewModel: starGazingIndexCardViewModel)
            }

            GlassEffectContainer {
                ViewThatFits(in: .horizontal) {
                    MacSummaryCardsWide(
                        summary: summary,
                        weather: weather,
                        isWeatherLoading: isWeatherLoading,
                        isForecastOutOfRange: viewModel.isCurrentWeatherForecastOutOfRange,
                        isCoverageIncomplete: viewModel.isCurrentWeatherCoverageIncomplete,
                        weatherViewModel: nightWeatherCardViewModel
                    )
                    MacSummaryCardsWrapped(
                        summary: summary,
                        weather: weather,
                        isWeatherLoading: isWeatherLoading,
                        isForecastOutOfRange: viewModel.isCurrentWeatherForecastOutOfRange,
                        isCoverageIncomplete: viewModel.isCurrentWeatherCoverageIncomplete,
                        weatherViewModel: nightWeatherCardViewModel
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private enum MacSummaryCardLayout {
    static let minimumWidth: CGFloat = LayoutMacOS.summaryCardMinWidth
}

private struct MacSummaryCardsWide: View {
    let summary: NightSummary
    let weather: DayWeatherSummary?
    let isWeatherLoading: Bool
    let isForecastOutOfRange: Bool
    let isCoverageIncomplete: Bool
    @ObservedObject var weatherViewModel: NightWeatherCardViewModel

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: MacSummaryCardLayout.minimumWidth), spacing: Spacing.xs),
                GridItem(.flexible(minimum: MacSummaryCardLayout.minimumWidth), spacing: Spacing.xs),
                GridItem(.flexible(minimum: MacSummaryCardLayout.minimumWidth), spacing: Spacing.xs),
                GridItem(.flexible(minimum: MacSummaryCardLayout.minimumWidth), spacing: Spacing.xs)
            ],
            alignment: .leading,
            spacing: Spacing.xs
        ) {
            DarkTimeCard(summary: summary, weather: weather)
            NightWeatherCard(
                weather: weather,
                isLoading: isWeatherLoading,
                isForecastOutOfRange: isForecastOutOfRange,
                isCoverageIncomplete: isCoverageIncomplete,
                errorMessage: nil,
                viewModel: weatherViewModel
            )
            MoonPhaseCard(summary: summary)
            MilkyWaySummaryCard(summary: summary)
        }
    }
}

private struct MacSummaryCardsWrapped: View {
    let summary: NightSummary
    let weather: DayWeatherSummary?
    let isWeatherLoading: Bool
    let isForecastOutOfRange: Bool
    let isCoverageIncomplete: Bool
    @ObservedObject var weatherViewModel: NightWeatherCardViewModel

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: MacSummaryCardLayout.minimumWidth), spacing: Spacing.xs)
            ],
            alignment: .leading,
            spacing: Spacing.xs
        ) {
            DarkTimeCard(summary: summary, weather: weather)
            NightWeatherCard(
                weather: weather,
                isLoading: isWeatherLoading,
                isForecastOutOfRange: isForecastOutOfRange,
                isCoverageIncomplete: isCoverageIncomplete,
                errorMessage: nil,
                viewModel: weatherViewModel
            )
            MoonPhaseCard(summary: summary)
            MilkyWaySummaryCard(summary: summary)
        }
    }
}

private struct MacStarMapSheet: View {
    @ObservedObject var viewModel: StarMapViewModel

    @State private var selectedStar: StarPosition?

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            StarMapCanvasView(viewModel: viewModel) { star in
                selectedStar = star
            }
            .frame(minWidth: StarMapLayout.canvasMinWidth, minHeight: StarMapLayout.canvasMinHeight)
            .popover(item: $selectedStar) { star in
                StarInfoMacView(starPosition: star)
            }

            Divider()
            statusSection
            controlsSection
        }
        .frame(minWidth: StarMapLayout.sheetMinWidth, minHeight: StarMapLayout.sheetMinHeight)
        .onDisappear {
            selectedStar = nil
        }
    }

    private var headerSection: some View {
        HStack {
            Text("星空マップ")
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            Button(action: viewModel.resetToNorth) {
                Label("北を向く", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.bordered)
            .help("北を向き、地平線を下端付近に合わせてリセット  [N]")

            Button(action: closeSheet) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("星空マップを閉じる")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    private var statusSection: some View {
        HStack(spacing: Spacing.md) {
            Label(
                String(format: "%@ %.0f°", StarMapPresentation.azimuthName(for: viewModel.viewAzimuth), viewModel.viewAzimuth),
                systemImage: "location.north.circle"
            )
            .font(.body)
            .foregroundStyle(.secondary)

            Label(
                String(format: "仰角 %.0f°", viewModel.viewAltitude),
                systemImage: "arrow.up.circle"
            )
            .font(.body)
            .foregroundStyle(.secondary)

            Label(
                String(format: "視野 %.0f°", viewModel.fov),
                systemImage: "viewfinder"
            )
            .font(.body)
            .foregroundStyle(.secondary)

            Spacer()

            if viewModel.moonAltitude > 0 {
                Label(
                    String(format: "月 %.0f°", viewModel.moonAltitude),
                    systemImage: "moon.fill"
                )
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
            }

            if !viewModel.meteorShowerRadiants.isEmpty {
                let shower = viewModel.meteorShowerRadiants[0].shower
                Label("\(shower.name) 活動中", systemImage: AppIcons.Astronomy.sparkles)
                    .font(.body)
                    .foregroundStyle(StarMapPalette.meteorAccent.opacity(0.9))
            } else if let next = viewModel.nextMeteorShower {
                Label("\(next.shower.name) まで\(next.daysUntilPeak)日", systemImage: AppIcons.Astronomy.sparkles)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    private var controlsSection: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Label("観測日", systemImage: AppIcons.Navigation.calendar)
                    .foregroundStyle(.secondary)
                    .font(.body)

                DatePicker("", selection: observationDateBinding, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .fixedSize()

                Spacer()

                Button("現在") {
                    viewModel.resetToNow()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            HStack(spacing: Spacing.sm) {
                Label("時刻", systemImage: AppIcons.Astronomy.moonStars)
                    .foregroundStyle(.secondary)
                    .font(.body)

                Slider(
                    value: timeSliderBinding,
                    in: 0...viewModel.timeSliderMaximumMinutes,
                    step: 1,
                    onEditingChanged: timeSliderEditingChanged
                )
                    .labelsHidden()

                Text(viewModel.displayTimeString)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: StarMapLayout.timeLabelWidth, alignment: .trailing)
            }
        }
        .padding(Spacing.sm)
    }

    private func closeSheet() {
        viewModel.isStarMapOpen = false
    }

    private var timeSliderBinding: Binding<Double> {
        Binding(
            get: { viewModel.timeSliderMinutes },
            set: { viewModel.setTimeSliderMinutes($0) }
        )
    }

    private var observationDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.observationDate },
            set: { viewModel.setObservationDate($0) }
        )
    }

    private func timeSliderEditingChanged(_ isEditing: Bool) {
        if isEditing {
            viewModel.beginTimeSliderInteraction()
        } else {
            viewModel.endTimeSliderInteraction()
        }
    }
}
