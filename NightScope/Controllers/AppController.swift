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

    private struct SelectedLocationContext {
        let coordinate: CLLocationCoordinate2D
        let timeZone: TimeZone
    }

    // MARK: - Dependencies
    let locationController: LocationController
    let weatherService: WeatherService
    let lightPollutionService: LightPollutionService

    // MARK: - Published State
    @Published var selectedDate: Date = Date() {
        didSet { publishObservationStateIfNeeded() }
    }
    @Published var nightSummary: NightSummary? {
        didSet { publishObservationStateIfNeeded() }
    }
    @Published var upcomingNights: [NightSummary] = [] {
        didSet { publishObservationStateIfNeeded() }
    }
    @Published var starGazingIndex: StarGazingIndex? {
        didSet { publishObservationStateIfNeeded() }
    }
    @Published var upcomingIndexes: [Date: StarGazingIndex] = [:] {
        didSet { publishObservationStateIfNeeded() }
    }
    @Published var isCalculating = false {
        didSet { publishObservationStateIfNeeded() }
    }
    @Published var isUpcomingLoading = false {
        didSet { publishObservationStateIfNeeded() }
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
    private var lastActiveReferenceDate: Date
    private var observationStateBatchDepth = 0

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
        self.selectedDate = ObservationTimeZone.startOfDay(
            for: Date(),
            timeZone: self.locationController.selectedTimeZone
        )
        self.lastActiveReferenceDate = Date()
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

    /// 初期表示に必要な計算と外部データ取得を一度だけ開始します。
    func onStart(referenceDate: Date = Date(), refreshExternalData: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        lastActiveReferenceDate = referenceDate
        selectedDate = ObservationTimeZone.startOfDay(for: referenceDate, timeZone: selectedTimeZone)
        recalculate()
        recalculateUpcoming(referenceDate: referenceDate)
        if refreshExternalData {
            refreshExternalDataInBackground()
        }
    }

    /// アプリが前景へ戻ったときに、日付跨ぎと外部データ更新を反映します。
    func handleSceneDidBecomeActive(referenceDate: Date = Date(), refreshExternalData: Bool = true) {
        guard hasStarted else {
            onStart(referenceDate: referenceDate, refreshExternalData: refreshExternalData)
            return
        }

        let timeZone = selectedTimeZone
        let previousActiveDay = ObservationTimeZone.startOfDay(
            for: lastActiveReferenceDate,
            timeZone: timeZone
        )
        let currentActiveDay = ObservationTimeZone.startOfDay(for: referenceDate, timeZone: timeZone)
        let wasTrackingToday = ObservationTimeZone.isDate(
            selectedDate,
            inSameDayAs: previousActiveDay,
            timeZone: timeZone
        )
        let dayDidChange = !ObservationTimeZone.isDate(
            previousActiveDay,
            inSameDayAs: currentActiveDay,
            timeZone: timeZone
        )

        lastActiveReferenceDate = referenceDate

        if dayDidChange && wasTrackingToday {
            selectedDate = currentActiveDay
            recalculate()
        }

        recalculateUpcoming(referenceDate: referenceDate)
        if refreshExternalData {
            refreshExternalDataInBackground()
        }
    }

    /// 選択中の観測地に対応する天気予報を更新します。
    func refreshWeather() async {
        let context = selectedLocationContext
        await weatherService.fetchWeather(
            latitude: context.coordinate.latitude,
            longitude: context.coordinate.longitude,
            timeZone: context.timeZone
        )
    }

    /// 選択中の観測地に対応する光害データを更新します。
    func refreshLightPollution() async {
        let context = selectedLocationContext
        await lightPollutionService.fetch(
            latitude: context.coordinate.latitude,
            longitude: context.coordinate.longitude
        )
    }

    /// 選択日を更新し、必要な当夜再計算を開始します。
    func selectObservationDate(_ date: Date, timeZone: TimeZone? = nil) {
        let effectiveTimeZone = timeZone ?? selectedTimeZone
        let normalizedDate = ObservationTimeZone.startOfDay(for: date, timeZone: effectiveTimeZone)
        guard !ObservationTimeZone.isDate(
            selectedDate,
            inSameDayAs: normalizedDate,
            timeZone: effectiveTimeZone
        ) else {
            return
        }
        selectedDate = normalizedDate
        recalculate()
    }

    /// 外部データ更新を fire-and-forget で開始します。
    func refreshExternalDataInBackground() {
        Task {
            await refreshExternalData()
        }
    }

    // MARK: - Calculation

    /// 選択中の観測日・観測地で当夜の集計を再計算します。
    func recalculate() {
        calculationTask?.cancel()
        performObservationStateBatchUpdate {
            isCalculating = true
            nightSummary = nil
            starGazingIndex = nil
        }
        let context = selectedLocationContext
        let date = selectedDate
        calculationTask = Task {
            let summary = await calculationService.calculateNightSummary(
                date: date,
                location: context.coordinate,
                timeZone: context.timeZone
            )
            guard !Task.isCancelled else { return }
            performObservationStateBatchUpdate {
                nightSummary = summary
                isCalculating = false
                recomputeStarGazingIndex()
            }
        }
    }

    /// 選択中の観測地に対する今後 14 日分の集計を再計算します。
    func recalculateUpcoming(referenceDate: Date = Date()) {
        upcomingTask?.cancel()
        isUpcomingLoading = true
        let context = selectedLocationContext
        let today = ObservationTimeZone.startOfDay(for: referenceDate, timeZone: context.timeZone)
        upcomingTask = Task {
            let upcoming = await calculationService.calculateUpcomingNights(
                from: today,
                location: context.coordinate,
                timeZone: context.timeZone,
                days: 14
            )
            guard !Task.isCancelled else { return }
            performObservationStateBatchUpdate {
                upcomingNights = upcoming
                recomputeUpcomingIndexes()
                isUpcomingLoading = false
            }
        }
    }

    /// 当夜の星空指数を最新の夜間サマリー・外部データから再構築します。
    func recomputeStarGazingIndex() {
        guard let summary = nightSummary else { return }
        starGazingIndex = makeStarGazingIndex(
            nightSummary: summary,
            weatherByDate: weatherService.weatherByDate,
            bortleClass: lightPollutionService.bortleClass
        )
    }

    /// 今後の夜ごとの星空指数一覧を最新の外部データから再構築します。
    func recomputeUpcomingIndexes() {
        let context = selectedLocationContext
        upcomingIndexes = makeUpcomingIndexes(
            upcomingNights: upcomingNights,
            weatherByDate: weatherService.weatherByDate,
            bortleClass: lightPollutionService.bortleClass,
            timeZone: context.timeZone
        )
    }

    // MARK: - Private
    private var selectedCoordinate: CLLocationCoordinate2D {
        locationController.selectedLocation
    }

    private var selectedTimeZone: TimeZone {
        locationController.selectedTimeZone
    }

    private var selectedLocationContext: SelectedLocationContext {
        SelectedLocationContext(
            coordinate: locationController.selectedLocation,
            timeZone: locationController.selectedTimeZone
        )
    }

    /// 場所変更後の再取得に備えて、既存の観測結果と外部データ状態を初期化します。
    func prepareForLocationChange() {
        prepareForLocationChange(using: selectedLocationContext)
    }

    /// 場所変更後の再取得に備えて、既存の観測結果と外部データ状態を初期化します。
    private func prepareForLocationChange(using context: SelectedLocationContext) {
        cancelActiveCalculationTasks()
        performObservationStateBatchUpdate {
            isCalculating = true
            isUpcomingLoading = true
            nightSummary = nil
            upcomingNights = []
            starGazingIndex = nil
            upcomingIndexes = [:]
        }
        weatherService.prepareForLocationChange(
            latitude: context.coordinate.latitude,
            longitude: context.coordinate.longitude,
            timeZone: context.timeZone
        )
        lightPollutionService.prepareForLocationChange()
    }

    private func refreshExternalData() async {
        await refreshWeather()
        await refreshLightPollution()
    }

    private func publishObservationStateIfNeeded() {
        guard observationStateBatchDepth == 0 else { return }
        publishObservationState()
    }

    private func publishObservationState() {
        observationState = ObservationState(appController: self)
    }

    private func performObservationStateBatchUpdate(_ updates: () -> Void) {
        observationStateBatchDepth += 1
        updates()
        observationStateBatchDepth -= 1
        guard observationStateBatchDepth == 0 else { return }
        publishObservationState()
    }

    private func recomputeAllIndexes() {
        performObservationStateBatchUpdate {
            recomputeStarGazingIndex()
            recomputeUpcomingIndexes()
        }
    }

    /// 観測地の変更に追従して、ローカル日付補正と関連データの一括再取得を行います。
    private func handleLocationChanged() async {
        let context = selectedLocationContext
        let timeZone = context.timeZone
        let request = prepareLocationRefreshRequest(context: context, timeZone: timeZone)
        let refreshResults = await fetchLocationRefreshResults(for: request, timeZone: timeZone)
        guard !Task.isCancelled else { return }
        let disposition = locationRefreshDisposition(for: request)
        guard disposition != .discard else { return }

        applyLocationRefresh(
            makeLocationRefreshPayload(
                selectedDate: request.selectedDate,
                context: context,
                nightSummary: refreshResults.nightSummary,
                upcomingNights: refreshResults.upcomingNights,
                weatherResult: refreshResults.weatherResult,
                lightPollutionResult: refreshResults.lightPollutionResult
            ),
            disposition: disposition
        )
    }

    private func prepareLocationRefreshRequest(
        context: SelectedLocationContext,
        timeZone: TimeZone
    ) -> LocationRefreshRequest {
        let normalizedDate = ObservationTimeZone.preservingCalendarDay(
            selectedDate,
            from: lastObservedTimeZone,
            to: timeZone
        )
        lastObservedTimeZone = timeZone
        performObservationStateBatchUpdate {
            selectedDate = ObservationTimeZone.startOfDay(for: normalizedDate, timeZone: timeZone)
            prepareForLocationChange(using: context)
        }
        return makeLocationRefreshRequest(selectedDate: selectedDate, context: context)
    }

    private func fetchLocationRefreshResults(
        for request: LocationRefreshRequest,
        timeZone: TimeZone
    ) async -> (
        nightSummary: NightSummary,
        upcomingNights: [NightSummary],
        weatherResult: WeatherService.FetchResult,
        lightPollutionResult: LightPollutionService.FetchResult
    ) {
        async let summaryTask = calculationService.calculateNightSummary(
            date: request.selectedDate,
            location: request.coordinate,
            timeZone: timeZone
        )
        async let upcomingTask = calculationService.calculateUpcomingNights(
            from: ObservationTimeZone.startOfDay(for: Date(), timeZone: timeZone),
            location: request.coordinate,
            timeZone: timeZone,
            days: 14
        )
        async let weatherTask = weatherService.fetchWeatherSnapshot(
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude,
            timeZone: timeZone
        )
        async let lightPollutionTask = lightPollutionService.fetchSnapshot(
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude
        )

        return await (
            nightSummary: summaryTask,
            upcomingNights: upcomingTask,
            weatherResult: weatherTask,
            lightPollutionResult: lightPollutionTask
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
        let context = selectedLocationContext
        guard Self.coordinatesEqual(context.coordinate, request.coordinate),
              context.timeZone.identifier == request.timeZoneIdentifier else {
            return .discard
        }

        if !ObservationTimeZone.isDate(
            selectedDate,
            inSameDayAs: request.selectedDate,
            timeZone: context.timeZone
        ) {
            return .applyLocationDataOnly
        }

        return .applyAll
    }

    /// 観測地変更で取得した一括データを、現在の選択状態に応じて安全に反映します。
    func applyLocationRefresh(
        _ payload: LocationRefreshPayload,
        disposition: LocationRefreshDisposition
    ) {
        isApplyingLocationRefresh = true
        weatherService.applyFetchResult(payload.weatherResult)
        lightPollutionService.applyFetchResult(payload.lightPollutionResult)
        performObservationStateBatchUpdate {
            upcomingNights = payload.upcomingNights
            upcomingIndexes = payload.upcomingIndexes
            isUpcomingLoading = false
        }
        isApplyingLocationRefresh = false

        switch disposition {
        case .discard:
            return
        case .applyAll:
            performObservationStateBatchUpdate {
                nightSummary = payload.nightSummary
                starGazingIndex = payload.starGazingIndex
                isCalculating = false
            }
        case .applyLocationDataOnly:
            if hasCurrentNightSummaryForSelection() {
                performObservationStateBatchUpdate {
                    recomputeStarGazingIndex()
                    isCalculating = false
                }
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
        bortleClass: Double?
    ) -> StarGazingIndex {
        let weather = weatherService.summary(
            for: nightSummary.date,
            from: weatherByDate,
            timeZone: nightSummary.timeZone
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
        return ObservationTimeZone.isDate(
            nightSummary.date,
            inSameDayAs: date,
            timeZone: timeZone
        )
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

    private func makeLocationRefreshRequest(
        selectedDate: Date,
        context: SelectedLocationContext
    ) -> LocationRefreshRequest {
        LocationRefreshRequest(
            selectedDate: selectedDate,
            coordinate: context.coordinate,
            timeZoneIdentifier: context.timeZone.identifier
        )
    }

    private func makeLocationRefreshPayload(
        selectedDate: Date,
        context: SelectedLocationContext,
        nightSummary: NightSummary,
        upcomingNights: [NightSummary],
        weatherResult: WeatherService.FetchResult,
        lightPollutionResult: LightPollutionService.FetchResult
    ) -> LocationRefreshPayload {
        LocationRefreshPayload(
            nightSummary: nightSummary,
            upcomingNights: upcomingNights,
            weatherResult: weatherResult,
            lightPollutionResult: lightPollutionResult,
            starGazingIndex: makeStarGazingIndex(
                nightSummary: nightSummary,
                weatherByDate: weatherResult.weatherByDate,
                bortleClass: lightPollutionResult.bortleClass
            ),
            upcomingIndexes: makeUpcomingIndexes(
                upcomingNights: upcomingNights,
                weatherByDate: weatherResult.weatherByDate,
                bortleClass: lightPollutionResult.bortleClass,
                timeZone: context.timeZone
            )
        )
    }
}

private extension AppController.ObservationState {
    @MainActor
    init(appController: AppController) {
        self.init(
            selectedDate: appController.selectedDate,
            nightSummary: appController.nightSummary,
            upcomingNights: appController.upcomingNights,
            starGazingIndex: appController.starGazingIndex,
            upcomingIndexes: appController.upcomingIndexes,
            isCalculating: appController.isCalculating,
            isUpcomingLoading: appController.isUpcomingLoading
        )
    }
}
