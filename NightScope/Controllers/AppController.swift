import Foundation
import Combine
import CoreLocation

@MainActor
final class AppController: ObservableObject {
    private struct LocationRefreshPayload {
        let nightSummary: NightSummary
        let upcomingNights: [NightSummary]
        let weatherResult: WeatherService.FetchResult
        let lightPollutionResult: LightPollutionService.FetchResult
        let starGazingIndex: StarGazingIndex
        let upcomingIndexes: [Date: StarGazingIndex]
    }

    // MARK: - Dependencies
    let locationController: LocationController
    let weatherService: WeatherService
    let lightPollutionService: LightPollutionService

    // MARK: - Published State
    @Published var selectedDate: Date = Date()
    @Published var nightSummary: NightSummary?
    @Published var upcomingNights: [NightSummary] = []
    @Published var starGazingIndex: StarGazingIndex?
    @Published var upcomingIndexes: [Date: StarGazingIndex] = [:]
    @Published var isCalculating = false
    @Published var isUpcomingLoading = false

    // MARK: - Private State
    private let calculationService: NightCalculating
    private var calculationTask: Task<Void, Never>?
    private var upcomingTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingLocationRefresh = false

    // MARK: - Init
    init(locationController: LocationController? = nil,
         weatherService: WeatherService? = nil,
         lightPollutionService: LightPollutionService? = nil,
         calculationService: NightCalculating? = nil) {
        self.locationController = locationController ?? LocationController()
        self.weatherService = weatherService ?? WeatherService()
        self.lightPollutionService = lightPollutionService ?? LightPollutionService()
        self.calculationService = calculationService ?? NightCalculationService()
        setupObservers()
        // 星カタログ（JSON 693KB）と色テーブルをバックグラウンドでプリウォーム。
        // StarMapViewModel が初回 _compute を実行する前に準備を完了させる。
        Task.detached(priority: .background) {
            _ = StarCatalog.stars.count
        }
    }

    deinit {
        calculationTask?.cancel()
        upcomingTask?.cancel()
        locationTask?.cancel()
    }

    // MARK: - Public Methods
    func onStart() {
        recalculate()
        recalculateUpcoming()
        refreshExternalDataInBackground()
    }

    func refreshWeather() async {
        let coordinate = selectedCoordinate
        await weatherService.fetchWeather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    func refreshLightPollution() async {
        let coordinate = selectedCoordinate
        await lightPollutionService.fetch(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    func refreshExternalDataInBackground() {
        Task {
            await refreshExternalData()
        }
    }

    // MARK: - Calculation
    func recalculate() {
        calculationTask?.cancel()
        isCalculating = true
        let date = selectedDate
        let location = selectedCoordinate
        calculationTask = Task {
            let summary = await calculationService.calculateNightSummary(date: date, location: location)
            guard !Task.isCancelled else { return }
            nightSummary = summary
            isCalculating = false
            recomputeStarGazingIndex()
        }
    }

    func recalculateUpcoming() {
        upcomingTask?.cancel()
        isUpcomingLoading = true
        let today = Date()
        let location = selectedCoordinate
        upcomingTask = Task {
            let upcoming = await calculationService.calculateUpcomingNights(from: today, location: location, days: 14)
            guard !Task.isCancelled else { return }
            upcomingNights = upcoming
            recomputeUpcomingIndexes()
            isUpcomingLoading = false
        }
    }

    func recomputeStarGazingIndex() {
        guard let summary = nightSummary else { return }
        starGazingIndex = makeStarGazingIndex(
            nightSummary: summary,
            weatherByDate: weatherService.weatherByDate,
            bortleClass: lightPollutionService.bortleClass,
            selectedDate: selectedDate
        )
    }

    func recomputeUpcomingIndexes() {
        upcomingIndexes = makeUpcomingIndexes(
            upcomingNights: upcomingNights,
            weatherByDate: weatherService.weatherByDate,
            bortleClass: lightPollutionService.bortleClass
        )
    }

    // MARK: - Private
    private var selectedCoordinate: CLLocationCoordinate2D {
        locationController.selectedLocation
    }

    func prepareForLocationChange() {
        cancelActiveCalculationTasks()
        isCalculating = true
        isUpcomingLoading = true
        let coordinate = selectedCoordinate
        weatherService.prepareForLocationChange(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        lightPollutionService.prepareForLocationChange()
    }

    private func refreshExternalData() async {
        await refreshWeather()
        await refreshLightPollution()
    }

    private func recomputeAllIndexes() {
        recomputeStarGazingIndex()
        recomputeUpcomingIndexes()
    }

    private func handleLocationChanged() async {
        prepareForLocationChange()
        let coordinate = selectedCoordinate
        let selectedDate = self.selectedDate

        async let summaryTask = calculationService.calculateNightSummary(date: selectedDate, location: coordinate)
        async let upcomingTask = calculationService.calculateUpcomingNights(from: Date(), location: coordinate, days: 14)
        async let weatherTask = weatherService.fetchWeatherSnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        async let lightPollutionTask = lightPollutionService.fetchSnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        let summary = await summaryTask
        let upcoming = await upcomingTask
        let weatherResult = await weatherTask
        let lightPollutionResult = await lightPollutionTask
        guard !Task.isCancelled else { return }
        let starGazingIndex = makeStarGazingIndex(
            nightSummary: summary,
            weatherByDate: weatherResult.weatherByDate,
            bortleClass: lightPollutionResult.bortleClass,
            selectedDate: selectedDate
        )
        let upcomingIndexes = makeUpcomingIndexes(
            upcomingNights: upcoming,
            weatherByDate: weatherResult.weatherByDate,
            bortleClass: lightPollutionResult.bortleClass
        )

        applyLocationRefresh(
            LocationRefreshPayload(
                nightSummary: summary,
                upcomingNights: upcoming,
                weatherResult: weatherResult,
                lightPollutionResult: lightPollutionResult,
                starGazingIndex: starGazingIndex,
                upcomingIndexes: upcomingIndexes
            )
        )
    }

    private func scheduleLocationChangeHandling() {
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self else { return }
            await handleLocationChanged()
        }
    }

    private func setupObservers() {
        locationController.$locationUpdateID
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleLocationChangeHandling()
            }
            .store(in: &cancellables)

        weatherService.$weatherByDate
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isApplyingLocationRefresh else { return }
                self.recomputeAllIndexes()
            }
            .store(in: &cancellables)

        lightPollutionService.bortleClassPublisher
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isApplyingLocationRefresh else { return }
                self.recomputeAllIndexes()
            }
            .store(in: &cancellables)
    }

    private func applyLocationRefresh(_ payload: LocationRefreshPayload) {
        isApplyingLocationRefresh = true
        weatherService.applyFetchResult(payload.weatherResult)
        lightPollutionService.applyFetchResult(payload.lightPollutionResult)
        nightSummary = payload.nightSummary
        upcomingNights = payload.upcomingNights
        starGazingIndex = payload.starGazingIndex
        upcomingIndexes = payload.upcomingIndexes
        isApplyingLocationRefresh = false
        isCalculating = false
        isUpcomingLoading = false
    }

    private func cancelActiveCalculationTasks() {
        calculationTask?.cancel()
        calculationTask = nil
        upcomingTask?.cancel()
        upcomingTask = nil
    }

    private func makeStarGazingIndex(
        nightSummary: NightSummary,
        weatherByDate: [String: DayWeatherSummary],
        bortleClass: Double?,
        selectedDate: Date
    ) -> StarGazingIndex {
        let weather = weatherByDate[weatherService.dateKey(selectedDate)]
        return StarGazingIndex.compute(
            nightSummary: nightSummary,
            weather: weather,
            bortleClass: bortleClass
        )
    }

    private func makeUpcomingIndexes(
        upcomingNights: [NightSummary],
        weatherByDate: [String: DayWeatherSummary],
        bortleClass: Double?
    ) -> [Date: StarGazingIndex] {
        var indexes: [Date: StarGazingIndex] = [:]
        for night in upcomingNights {
            let weather = weatherByDate[weatherService.dateKey(night.date)]
            let idx = StarGazingIndex.compute(nightSummary: night, weather: weather, bortleClass: bortleClass)
            indexes[Calendar.current.startOfDay(for: night.date)] = idx
        }
        return indexes
    }
}
