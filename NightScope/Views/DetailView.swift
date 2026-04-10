import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var starGazingIndexCardViewModel: StarGazingIndexCardViewModel
    @StateObject private var nightWeatherCardViewModel: NightWeatherCardViewModel
    @StateObject private var upcomingGridViewModel: UpcomingNightsGridViewModel
    @ObservedObject var starMapViewModel: StarMapViewModel

    @State private var selectedStar: StarPosition? = nil

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
            macStarMapSheet
        }
        .overlay(alignment: .bottom, content: errorOverlay)
        .animation(reduceMotion ? .none : .standard, value: viewModel.hasWeatherError)
        .animation(reduceMotion ? .none : .standard, value: viewModel.hasLightPollutionError)
    }

    // MARK: - macOS Star Map Sheet

    private var macStarMapSheet: some View {
        VStack(spacing: 0) {
            // ---- ヘッダー ----
            HStack {
                Text("星空マップ")
                    .font(.headline)
                Spacer()
                Button {
                    starMapViewModel.resetToNorth()
                } label: {
                    Label("北を向く", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("北 (方位0°, 仰角30°) にリセット  [N]")

                Button {
                    starMapViewModel.isStarMapOpen = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            }
            .padding(Spacing.sm)

            // ---- キャンバス ----
            StarMapCanvasView(viewModel: starMapViewModel, onStarSelected: { star in
                selectedStar = star
            })
            .frame(minWidth: 560, minHeight: 480)
            .popover(item: $selectedStar) { star in
                StarInfoMacView(starPosition: star)
            }

            Divider()

            // ---- ステータス HUD ----
            HStack(spacing: Spacing.md) {
                Label(
                    String(format: "%@ %.0f°",
                           azimuthName(starMapViewModel.viewAzimuth),
                           starMapViewModel.viewAzimuth),
                    systemImage: "location.north.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    String(format: "仰角 %.0f°", starMapViewModel.viewAltitude),
                    systemImage: "arrow.up.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    String(format: "視野 %.0f°", starMapViewModel.fov),
                    systemImage: "viewfinder"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if starMapViewModel.sunAltitude > 0 {
                    Label(
                        String(format: "太陽 %.0f°", starMapViewModel.sunAltitude),
                        systemImage: "sun.max.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.yellow)
                }
                if starMapViewModel.moonAltitude > 0 {
                    Label(
                        String(format: "月 %.0f°", starMapViewModel.moonAltitude),
                        systemImage: "moon.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            Divider()

            // ---- コントロール ----
            HStack(spacing: Spacing.sm) {
                Label("観測日時", systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                DatePicker(
                    "",
                    selection: $starMapViewModel.displayDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button("現在") {
                    starMapViewModel.resetToNow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if !starMapViewModel.isNight {
                    Label("昼間", systemImage: "sun.max")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            .padding(Spacing.sm)
        }
        .frame(minWidth: 600, minHeight: 640)
    }

    /// 方位角 (度) を 8 方位の日本語テキストに変換する
    private func azimuthName(_ degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % 8
        let names = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        return names[index]
    }

    private func detailContent(summary: NightSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection(summary: summary)
                ViewingWindowsSection(summary: summary)
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
                    retryAction: viewModel.retryLightPollutionInBackground
                )
            }
            if let error = viewModel.weatherErrorMessage {
                errorBanner(
                    message: error,
                    retryAction: viewModel.retryWeatherInBackground
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
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Text("星空観測情報")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        starMapViewModel.isStarMapOpen = true
                    } label: {
                        Label("星空マップ", systemImage: "sparkles")
                    }
                    .help("星空マップを表示")
                }
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
