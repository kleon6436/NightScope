import Foundation
import Combine
import CoreLocation

@MainActor
final class AppController: ObservableObject {
    struct ObservationState {
        var selectedDate = Date()
        var nightSummary: NightSummary?
        var upcomingNights: [NightSummary] = []
        var starGazingIndex: StarGazingIndex?
        var upcomingIndexes: [Date: StarGazingIndex] = [:]
        var isCalculating = false
        var isUpcomingLoading = false
    }

    struct LocationRefreshRequest {
        let selectedDate: Date
        let coordinate: CLLocationCoordinate2D
        let timeZoneIdentifier: String
    }

    enum LocationRefreshDisposition: Equatable {
        case discard
        case applyAll
        case applyLocationDataOnly
    }

    struct LocationRefreshPayload {
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
    @Published var selectedDate: Date = Date() {
        didSet { publishObservationState() }
    }
    @Published var nightSummary: NightSummary? {
        didSet { publishObservationState() }
    }
    @Published var upcomingNights: [NightSummary] = [] {
        didSet { publishObservationState() }
    }
    @Published var starGazingIndex: StarGazingIndex? {
        didSet { publishObservationState() }
    }
    @Published var upcomingIndexes: [Date: StarGazingIndex] = [:] {
        didSet { publishObservationState() }
    }
    @Published var isCalculating = false {
        didSet { publishObservationState() }
    }
    @Published var isUpcomingLoading = false {
        didSet { publishObservationState() }
    }
    @Published private(set) var observationState = ObservationState()

    // MARK: - Private State
    private let calculationService: NightCalculating
    private var calculationTask: Task<Void, Never>?
    private var upcomingTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingLocationRefresh = false
    private var hasStarted = false
    private var lastObservedTimeZone: TimeZone

    // MARK: - Init
    init(locationController: LocationController? = nil,
         weatherService: WeatherService? = nil,
         lightPollutionService: LightPollutionService? = nil,
         calculationService: NightCalculating? = nil) {
        self.locationController = locationController ?? LocationController()
        self.weatherService = weatherService ?? WeatherService()
        self.lightPollutionService = lightPollutionService ?? LightPollutionService()
        self.calculationService = calculationService ?? NightCalculationService()
        self.lastObservedTimeZone = self.locationController.selectedTimeZone
        publishObservationState()
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
        guard !hasStarted else { return }
        hasStarted = true
        recalculate()
        recalculateUpcoming()
        refreshExternalDataInBackground()
    }

    func refreshWeather() async {
        let coordinate = selectedCoordinate
        await weatherService.fetchWeather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZone: selectedTimeZone
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
        let timeZone = selectedTimeZone
        calculationTask = Task {
            let summary = await calculationService.calculateNightSummary(
                date: date,
                location: location,
                timeZone: timeZone
            )
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
        let timeZone = selectedTimeZone
        upcomingTask = Task {
            let upcoming = await calculationService.calculateUpcomingNights(
                from: today,
                location: location,
                timeZone: timeZone,
                days: 14
            )
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
            selectedDate: selectedDate,
            timeZone: selectedTimeZone
        )
    }

    func recomputeUpcomingIndexes() {
        upcomingIndexes = makeUpcomingIndexes(
            upcomingNights: upcomingNights,
            weatherByDate: weatherService.weatherByDate,
            bortleClass: lightPollutionService.bortleClass,
            timeZone: selectedTimeZone
        )
    }

    // MARK: - Private
    private var selectedCoordinate: CLLocationCoordinate2D {
        locationController.selectedLocation
    }

    private var selectedTimeZone: TimeZone {
        locationController.selectedTimeZone
    }

    func prepareForLocationChange() {
        cancelActiveCalculationTasks()
        isCalculating = true
        isUpcomingLoading = true
        nightSummary = nil
        upcomingNights = []
        starGazingIndex = nil
        upcomingIndexes = [:]
        let coordinate = selectedCoordinate
        weatherService.prepareForLocationChange(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZone: selectedTimeZone
        )
        lightPollutionService.prepareForLocationChange()
    }

    private func refreshExternalData() async {
        await refreshWeather()
        await refreshLightPollution()
    }

    private func publishObservationState() {
        observationState = ObservationState(
            selectedDate: selectedDate,
            nightSummary: nightSummary,
            upcomingNights: upcomingNights,
            starGazingIndex: starGazingIndex,
            upcomingIndexes: upcomingIndexes,
            isCalculating: isCalculating,
            isUpcomingLoading: isUpcomingLoading
        )
    }

    private func recomputeAllIndexes() {
        recomputeStarGazingIndex()
        recomputeUpcomingIndexes()
    }

    private func handleLocationChanged() async {
        let timeZone = selectedTimeZone
        let normalizedDate = ObservationTimeZone.preservingCalendarDay(
            selectedDate,
            from: lastObservedTimeZone,
            to: timeZone
        )
        lastObservedTimeZone = timeZone
        selectedDate = ObservationTimeZone.startOfDay(for: normalizedDate, timeZone: timeZone)
        prepareForLocationChange()
        let coordinate = selectedCoordinate
        let selectedDate = self.selectedDate
        let request = LocationRefreshRequest(
            selectedDate: selectedDate,
            coordinate: coordinate,
            timeZoneIdentifier: timeZone.identifier
        )

        async let summaryTask = calculationService.calculateNightSummary(
            date: selectedDate,
            location: coordinate,
            timeZone: timeZone
        )
        async let upcomingTask = calculationService.calculateUpcomingNights(
            from: Date(),
            location: coordinate,
            timeZone: timeZone,
            days: 14
        )
        async let weatherTask = weatherService.fetchWeatherSnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZone: timeZone
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
            selectedDate: selectedDate,
            timeZone: timeZone
        )
        let upcomingIndexes = makeUpcomingIndexes(
            upcomingNights: upcoming,
            weatherByDate: weatherResult.weatherByDate,
            bortleClass: lightPollutionResult.bortleClass,
            timeZone: timeZone
        )
        let disposition = locationRefreshDisposition(for: request)
        guard disposition != .discard else { return }

        applyLocationRefresh(
            LocationRefreshPayload(
                nightSummary: summary,
                upcomingNights: upcoming,
                weatherResult: weatherResult,
                lightPollutionResult: lightPollutionResult,
                starGazingIndex: starGazingIndex,
                upcomingIndexes: upcomingIndexes
            ),
            disposition: disposition
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

        locationController.selectedTimeZonePublisher
            .dropFirst()
            .removeDuplicates { $0.identifier == $1.identifier }
            .sink { [weak self] _ in
                self?.handleSelectedTimeZoneChanged()
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

    func locationRefreshDisposition(for request: LocationRefreshRequest) -> LocationRefreshDisposition {
        guard Self.coordinatesEqual(selectedCoordinate, request.coordinate),
              selectedTimeZone.identifier == request.timeZoneIdentifier else {
            return .discard
        }

        if selectedDate != request.selectedDate {
            return .applyLocationDataOnly
        }

        return .applyAll
    }

    func applyLocationRefresh(
        _ payload: LocationRefreshPayload,
        disposition: LocationRefreshDisposition
    ) {
        isApplyingLocationRefresh = true
        weatherService.applyFetchResult(payload.weatherResult)
        lightPollutionService.applyFetchResult(payload.lightPollutionResult)
        upcomingNights = payload.upcomingNights
        upcomingIndexes = payload.upcomingIndexes
        isApplyingLocationRefresh = false
        isUpcomingLoading = false

        switch disposition {
        case .discard:
            return
        case .applyAll:
            nightSummary = payload.nightSummary
            starGazingIndex = payload.starGazingIndex
            isCalculating = false
        case .applyLocationDataOnly:
            if hasCurrentNightSummaryForSelection() {
                recomputeStarGazingIndex()
                isCalculating = false
            } else {
                isCalculating = false
                recalculateCurrentNightIfNeeded()
            }
        }
    }

    private func handleSelectedTimeZoneChanged() {
        let newTimeZone = selectedTimeZone
        let previousTimeZone = lastObservedTimeZone
        lastObservedTimeZone = newTimeZone

        let normalizedDate = ObservationTimeZone.preservingCalendarDay(
            selectedDate,
            from: previousTimeZone,
            to: newTimeZone
        )
        guard normalizedDate != selectedDate else { return }
        selectedDate = normalizedDate
    }

    private func cancelActiveCalculationTasks() {
        calculationTask?.cancel()
        calculationTask = nil
        upcomingTask?.cancel()
        upcomingTask = nil
    }

    func makeStarGazingIndex(
        nightSummary: NightSummary,
        weatherByDate: [String: DayWeatherSummary],
        bortleClass: Double?,
        selectedDate: Date,
        timeZone: TimeZone
    ) -> StarGazingIndex {
        let weather = weatherService.summary(
            for: selectedDate,
            from: weatherByDate,
            timeZone: timeZone
        )
        return StarGazingIndex.compute(
            nightSummary: nightSummary,
            weather: weather,
            bortleClass: bortleClass
        )
    }

    func makeUpcomingIndexes(
        upcomingNights: [NightSummary],
        weatherByDate: [String: DayWeatherSummary],
        bortleClass: Double?,
        timeZone: TimeZone
    ) -> [Date: StarGazingIndex] {
        var indexes: [Date: StarGazingIndex] = [:]
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        for night in upcomingNights {
            let weather = weatherService.summary(
                for: night.date,
                from: weatherByDate,
                timeZone: timeZone
            )
            let idx = StarGazingIndex.compute(nightSummary: night, weather: weather, bortleClass: bortleClass)
            indexes[calendar.startOfDay(for: night.date)] = idx
        }
        return indexes
    }

    private func hasCurrentNightSummaryForSelection() -> Bool {
        hasNightSummary(matching: selectedDate, location: selectedCoordinate, timeZone: selectedTimeZone)
    }

    private func hasNightSummary(
        matching date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Bool {
        guard let nightSummary else { return false }
        return nightSummary.date == date
            && Self.coordinatesEqual(nightSummary.location, location)
            && nightSummary.timeZoneIdentifier == timeZone.identifier
    }

    private func recalculateCurrentNightIfNeeded() {
        guard !isCalculating else { return }
        guard !hasCurrentNightSummaryForSelection() else { return }
        recalculate()
    }

    private static func coordinatesEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
