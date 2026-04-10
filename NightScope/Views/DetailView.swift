import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var starGazingIndexCardViewModel: StarGazingIndexCardViewModel
    @StateObject private var nightWeatherCardViewModel: NightWeatherCardViewModel
    @StateObject private var upcomingGridViewModel: UpcomingNightsGridViewModel
    @ObservedObject var starMapViewModel: StarMapViewModel

    @State private var selectedStar: StarPosition? = nil
    /// 時刻スライダー用: 0=00:00, 1439=23:59（分単位）
    @State private var timeSliderMinutes: Double = 0

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
        .onChange(of: starMapViewModel.isStarMapOpen) { _, isOpen in
            if isOpen { starMapViewModel.syncWithSelectedDate() }
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

                // タイムラプス速度選択
                Picker("速度", selection: $starMapViewModel.timelapseSpeed) {
                    Text("×10").tag(10.0)
                    Text("×60").tag(60.0)
                    Text("×600").tag(600.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .controlSize(.small)
                .help("タイムラプス速度 (×10=10倍速 / ×60=1分/秒 / ×600=10分/秒)")

                // 再生/停止ボタン
                Button {
                    starMapViewModel.toggleTimelapse()
                } label: {
                    Image(systemName: starMapViewModel.isTimelapsePlaying
                          ? "pause.circle.fill" : "play.circle.fill")
                        .symbolEffect(.bounce, value: starMapViewModel.isTimelapsePlaying)
                        .font(.title3)
                        .foregroundStyle(starMapViewModel.isTimelapsePlaying ? .yellow : .accentColor)
                }
                .buttonStyle(.plain)
                .help(starMapViewModel.isTimelapsePlaying ? "タイムラプスを停止" : "タイムラプスを再生")

                Button {
                    starMapViewModel.resetToNorth()
                } label: {
                    Label("北を向く", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("北 (方位0°, 仰角30°) にリセット  [N]")

                Button {
                    starMapViewModel.stopTimelapse()
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
            .frame(minWidth: 720, minHeight: 560)
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

                // 流星群情報
                if !starMapViewModel.meteorShowerRadiants.isEmpty {
                    let shower = starMapViewModel.meteorShowerRadiants[0].shower
                    Label("\(shower.name) 活動中", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.7).opacity(0.9))
                } else if let next = starMapViewModel.nextMeteorShower {
                    Label("次: \(next.shower.name) (\(next.daysUntilPeak)日後)", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            Divider()

            // ---- コントロール ----
            VStack(spacing: 4) {
                HStack(spacing: Spacing.sm) {
                    Label("観測日", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                    DatePicker(
                        "",
                        selection: $starMapViewModel.displayDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: starMapViewModel.displayDate) { _, newDate in
                        let cal = Calendar.current
                        let comps = cal.dateComponents([.hour, .minute], from: newDate)
                        let mins = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
                        if abs(timeSliderMinutes - mins) > 0.5 {
                            timeSliderMinutes = mins
                        }
                    }

                    Spacer()

                    if !starMapViewModel.isNight {
                        Label("昼間", systemImage: "sun.max")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Button("現在") {
                        starMapViewModel.resetToNow()
                        syncSliderToDisplayDate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "moon.stars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Slider(value: $timeSliderMinutes, in: 0...1439, step: 1) {
                        Text("時刻")
                    }
                    .onChange(of: timeSliderMinutes) { _, mins in
                        applySliderToDisplayDate(minutes: mins)
                    }

                    Text(timeString(from: timeSliderMinutes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .padding(Spacing.sm)
            .onAppear { syncSliderToDisplayDate() }
            .onChange(of: starMapViewModel.displayDate) { _, _ in
                // タイムラプス再生中はスライダーを追従させる
                if starMapViewModel.isTimelapsePlaying {
                    syncSliderToDisplayDate()
                }
            }
        }
        .frame(minWidth: 760, minHeight: 720)
    }

    /// 方位角 (度) を 8 方位の日本語テキストに変換する
    private func azimuthName(_ degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % 8
        let names = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        return names[index]
    }

    /// スライダー値 (分) を "HH:mm" 文字列に変換
    private func timeString(from minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return String(format: "%02d:%02d", h, m)
    }

    /// displayDate の時分をスライダーに反映
    private func syncSliderToDisplayDate() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: starMapViewModel.displayDate)
        timeSliderMinutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    /// スライダー値 (分) を displayDate に反映
    private func applySliderToDisplayDate(minutes: Double) {
        let cal = Calendar.current
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        if let updated = cal.date(bySettingHour: h, minute: m, second: 0,
                                   of: starMapViewModel.displayDate) {
            starMapViewModel.displayDate = updated
        }
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
