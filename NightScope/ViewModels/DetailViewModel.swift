import SwiftUI
import Combine

/// 画面に表示する状態を「読み込み中 / 空 / 表示可」に畳み込む。
enum LoadableContentState: Equatable {
    case loading
    case empty
    case content
}

/// 詳細画面のカード表示可否をまとめて判定する。
struct DetailContentStateResolver {
    /// 直近予報の読み込み状況から、予報カードの表示状態を返す。
    func forecastState(hasDisplayNights: Bool, isUpcomingLoading: Bool) -> LoadableContentState {
        if isUpcomingLoading && !hasDisplayNights {
            return .loading
        }
        if !hasDisplayNights {
            return .empty
        }
        return .content
    }

    /// 当日の詳細表示に必要な夜間データの有無を判定する。
    func todayState(isCalculating: Bool, summary: NightSummary?) -> LoadableContentState {
        if isCalculating && summary == nil {
            return .loading
        }
        if summary == nil {
            return .empty
        }
        return .content
    }
}

@MainActor
/// 観測日の詳細情報と再計算状態を管理する ViewModel。
final class DetailViewModel: ObservableObject {
    /// 現在表示している当日詳細の元データ。
    @Published private(set) var nightSummary: NightSummary?
    /// 調整後の星空指数。
    @Published private(set) var starGazingIndex: StarGazingIndex?
    /// 選択中の観測モード。
    @Published private(set) var observationMode: ObservationMode
    /// 再計算中かどうか。
    @Published private(set) var isCalculating = false
    /// 予報対象の未来数日分。
    @Published private(set) var upcomingNights: [NightSummary] = []
    /// 日付ごとの星空指数キャッシュ。
    @Published private(set) var upcomingIndexes: [Date: StarGazingIndex] = [:]
    @Published var selectedDate: Date
    /// 表示上の観測日。再計算中は一時的に前回表示を保持する。
    @Published private(set) var displayedDate: Date
    @Published private(set) var locationName: String = ""
    @Published private(set) var hasWeatherError: Bool = false
    @Published private(set) var weatherErrorMessage: String? = nil
    @Published private(set) var hasLightPollutionError: Bool = false
    @Published private(set) var currentWeather: DayWeatherSummary?
    @Published private(set) var isWeatherLoading: Bool = false
    @Published private(set) var isUpcomingLoading: Bool = false
    @Published private(set) var selectedTimeZone: TimeZone
    @Published private(set) var isCurrentWeatherForecastOutOfRange = false
    @Published private(set) var isCurrentWeatherCoverageIncomplete = false

    private let appController: AppController
    private let observationModePreference: ObservationModePreference
    private var cancellables = Set<AnyCancellable>()

    /// AppController の観測状態を詳細画面向けに同期する。
    init(
        appController: AppController,
        observationModePreference: ObservationModePreference = ObservationModePreference()
    ) {
        self.appController = appController
        self.observationModePreference = observationModePreference
        let initialState = appController.observationState
        self.nightSummary = initialState.nightSummary
        self.starGazingIndex = initialState.starGazingIndex
        self.observationMode = observationModePreference.mode
        self.isCalculating = initialState.isCalculating
        self.upcomingNights = initialState.upcomingNights
        self.upcomingIndexes = initialState.upcomingIndexes
        self.selectedDate = initialState.selectedDate
        self.displayedDate = initialState.selectedDate
        self.selectedTimeZone = appController.locationController.selectedTimeZone
        bind()
        updateDisplayedContentState()
    }

    private func bind() {
        appController.$observationState
            .sink { [weak self] state in
                guard let self else { return }
                if !self.shouldPreserveDisplayedSummary(during: state) {
                    self.nightSummary = state.nightSummary
                    self.starGazingIndex = state.starGazingIndex
                }
                self.upcomingNights = state.upcomingNights
                self.upcomingIndexes = state.upcomingIndexes
                self.isCalculating = state.isCalculating
                self.isUpcomingLoading = state.isUpcomingLoading
                if self.selectedDate != state.selectedDate {
                    self.selectedDate = state.selectedDate
                }
                self.updateDisplayedContentState()
            }
            .store(in: &cancellables)

        appController.weatherService.weatherByDatePublisher
            .sink { [weak self] _ in
                self?.updateDisplayedContentState()
            }
            .store(in: &cancellables)

        $selectedDate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] date in
                guard let self else { return }
                let normalizedDate = ObservationTimeZone.startOfDay(
                    for: date,
                    timeZone: self.selectedTimeZone
                )
                guard !ObservationTimeZone.isDate(
                    self.appController.selectedDate,
                    inSameDayAs: normalizedDate,
                    timeZone: self.selectedTimeZone
                ) else {
                    return
                }
                self.appController.selectObservationDate(
                    normalizedDate,
                    timeZone: self.selectedTimeZone
                )
            }
            .store(in: &cancellables)

        appController.locationController.$locationName
            .assign(to: &$locationName)

        appController.locationController.selectedTimeZonePublisher
            .sink { [weak self] timeZone in
                guard let self else { return }
                self.selectedTimeZone = timeZone
                self.updateDisplayedContentState()
            }
            .store(in: &cancellables)

        appController.weatherService.errorMessagePublisher
            .sink { [weak self] errorMessage in
                self?.weatherErrorMessage = errorMessage
                self?.hasWeatherError = errorMessage != nil
            }
            .store(in: &cancellables)

        appController.weatherService.isLoadingPublisher
            .assign(to: &$isWeatherLoading)

        appController.lightPollutionService.$fetchFailed
            .assign(to: &$hasLightPollutionError)

        observationModePreference.$mode
            .removeDuplicates()
            .assign(to: &$observationMode)
    }

    var weatherService: any WeatherProviding {
        appController.weatherService
    }

    var lightPollutionService: LightPollutionService {
        appController.lightPollutionService
    }

    var displayedStarGazingIndex: StarGazingIndex? {
        guard let starGazingIndex else { return nil }
        guard let nightSummary else { return starGazingIndex }
        return starGazingIndex.adjusted(
            for: observationMode,
            nightSummary: nightSummary,
            weather: currentWeather
        )
    }

    /// 天気情報を再取得する。
    func refreshWeather() async {
        await appController.refreshWeather()
    }

    /// 光害情報を再取得する。
    func refreshLightPollution() async {
        await appController.refreshLightPollution()
    }

    /// 当日詳細に必要な外部データをまとめて更新する。
    func refreshExternalData() async {
        await appController.refreshExternalData()
    }

    /// 未来予報を再計算する。
    func refreshForecast() async {
        await appController.recalculateUpcomingAndWait()
    }

    /// バックグラウンドで天気再取得を行う。
    func retryWeatherInBackground() {
        Task {
            await refreshWeather()
        }
    }

    /// バックグラウンドで光害再取得を行う。
    func retryLightPollutionInBackground() {
        Task {
            await refreshLightPollution()
        }
    }

    /// バックグラウンドで予報再計算を行う。
    func retryForecastInBackground() {
        Task {
            await refreshForecast()
        }
    }

    private var effectiveDisplayDate: Date {
        guard isCalculating,
              let nightSummary,
              !ObservationTimeZone.isDate(
                nightSummary.date,
                inSameDayAs: selectedDate,
                timeZone: selectedTimeZone
              ) else {
            return selectedDate
        }

        return nightSummary.date
    }

    private func shouldPreserveDisplayedSummary(
        during state: AppController.ObservationState
    ) -> Bool {
        // 同じ地点・同じタイムゾーンで日付だけ変わった場合は、再計算中も前回表示を残す。
        guard state.isCalculating,
              state.nightSummary == nil,
              let displayedSummary = nightSummary else {
            return false
        }

        let selectedCoordinate = appController.locationController.selectedLocation
        let isSameLocation =
            displayedSummary.location.latitude == selectedCoordinate.latitude
            && displayedSummary.location.longitude == selectedCoordinate.longitude
        let isSameTimeZone = displayedSummary.timeZoneIdentifier == selectedTimeZone.identifier
        let isRefreshingDifferentDay = !ObservationTimeZone.isDate(
            displayedSummary.date,
            inSameDayAs: state.selectedDate,
            timeZone: selectedTimeZone
        )

        return isSameLocation && isSameTimeZone && isRefreshingDifferentDay
    }

    private func updateDisplayedContentState() {
        // 表示中の日付に対応する天気と星空指数を、観測タイムゾーン基準で揃える。
        displayedDate = effectiveDisplayDate
        let weatherByDate = appController.weatherService.weatherByDate
        currentWeather = appController.weatherService.summary(
            for: displayedDate,
            from: weatherByDate,
            timeZone: selectedTimeZone
        )
        isCurrentWeatherCoverageIncomplete = {
            guard let nightSummary, let currentWeather else { return false }
            return !nightSummary.hasUsableWeatherData(nighttimeHours: currentWeather.nighttimeHours)
        }()
        isCurrentWeatherForecastOutOfRange = appController.weatherService.isForecastOutOfRange(
            for: displayedDate,
            in: weatherByDate,
            timeZone: selectedTimeZone
        )
    }
}
