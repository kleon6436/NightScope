import SwiftUI
import Combine

enum LoadableContentState: Equatable {
    case loading
    case empty
    case content
}

struct DetailContentStateResolver {
    func forecastState(hasDisplayNights: Bool, isUpcomingLoading: Bool) -> LoadableContentState {
        if isUpcomingLoading && !hasDisplayNights {
            return .loading
        }
        if !hasDisplayNights {
            return .empty
        }
        return .content
    }

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
final class DetailViewModel: ObservableObject {
    @Published private(set) var nightSummary: NightSummary?
    @Published private(set) var starGazingIndex: StarGazingIndex?
    @Published private(set) var isCalculating = false
    @Published private(set) var upcomingNights: [NightSummary] = []
    @Published private(set) var upcomingIndexes: [Date: StarGazingIndex] = [:]
    @Published var selectedDate: Date
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
    private var cancellables = Set<AnyCancellable>()

    init(appController: AppController) {
        self.appController = appController
        let initialState = appController.observationState
        self.nightSummary = initialState.nightSummary
        self.starGazingIndex = initialState.starGazingIndex
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
    }

    var weatherService: any WeatherProviding {
        appController.weatherService
    }

    var lightPollutionService: LightPollutionService {
        appController.lightPollutionService
    }

    func refreshWeather() async {
        await appController.refreshWeather()
    }

    func refreshLightPollution() async {
        await appController.refreshLightPollution()
    }

    func refreshExternalData() async {
        await appController.refreshExternalData()
    }

    func refreshForecast() async {
        await appController.recalculateUpcomingAndWait()
    }

    func retryWeatherInBackground() {
        Task {
            await refreshWeather()
        }
    }

    func retryLightPollutionInBackground() {
        Task {
            await refreshLightPollution()
        }
    }

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
        displayedDate = effectiveDisplayDate
        let weatherByDate = appController.weatherService.weatherByDate
        currentWeather = appController.weatherService.summary(
            for: displayedDate,
            from: weatherByDate,
            timeZone: selectedTimeZone
        )
        isCurrentWeatherCoverageIncomplete = {
            guard let nightSummary, let currentWeather else { return false }
            return !nightSummary.hasReliableWeatherData(nighttimeHours: currentWeather.nighttimeHours)
        }()
        isCurrentWeatherForecastOutOfRange = appController.weatherService.isForecastOutOfRange(
            for: displayedDate,
            in: weatherByDate,
            timeZone: selectedTimeZone
        )
    }
}
