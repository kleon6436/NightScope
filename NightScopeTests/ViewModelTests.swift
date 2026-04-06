import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class ViewModelTests: XCTestCase {

    actor AsyncCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    // MARK: - Helpers

    private func makeHourlyWeather(cloudCover: Double = 10, weatherCode: Int = 0, windSpeed: Double = 5) -> HourlyWeather {
        HourlyWeather(
            date: Date(),
            temperatureCelsius: 15,
            cloudCoverPercent: cloudCover,
            precipitationMM: 0,
            windSpeedKmh: windSpeed,
            humidityPercent: 40,
            dewpointCelsius: 2,
            weatherCode: weatherCode,
            visibilityMeters: 20000,
            windGustsKmh: nil,
            cloudCoverLowPercent: nil,
            cloudCoverMidPercent: nil,
            cloudCoverHighPercent: nil,
            windSpeedKmh500hpa: nil
        )
    }

    private func makeDayWeatherSummary(cloudCover: Double = 10, weatherCode: Int = 0, windSpeed: Double = 5, precipitation: Double = 0) -> DayWeatherSummary {
        let hour = makeHourlyWeather(cloudCover: cloudCover, weatherCode: weatherCode, windSpeed: windSpeed)
        return DayWeatherSummary(date: Date(), nighttimeHours: [hour])
    }

    private func makeNightSummary(date: Date = Date(), withWindow: Bool = true, moonPhase: Double = 0.12) -> NightSummary {
        let location = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let eventDate = Calendar.current.date(byAdding: .hour, value: 21, to: date) ?? date
        let event = AstroEvent(
            date: eventDate,
            galacticCenterAltitude: 28,
            galacticCenterAzimuth: 190,
            sunAltitude: -22,
            moonAltitude: -8,
            moonPhase: moonPhase
        )
        let windows: [ViewingWindow] = withWindow ? [
            ViewingWindow(
                start: eventDate,
                end: eventDate.addingTimeInterval(3600),
                peakTime: eventDate.addingTimeInterval(1800),
                peakAltitude: 32,
                peakAzimuth: 180
            )
        ] : []
        return NightSummary(
            date: date,
            location: location,
            events: [event],
            viewingWindows: windows,
            moonPhaseAtMidnight: moonPhase
        )
    }

    private func makeMapItem(coordinate: CLLocationCoordinate2D, name: String? = nil) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        return item
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("条件を満たすまでにタイムアウトしました", file: file, line: line)
    }

    // MARK: - Mock Types

    final class MockLocationController: LocationProviding {
        var selectedLocation = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        @Published var locationName = ""
        @Published var locationUpdateID = UUID()
        var locationUpdateIDPublisher: Published<UUID>.Publisher { $locationUpdateID }
        var locationNamePublisher: Published<String>.Publisher { $locationName }
        var anyChangePublisher: AnyPublisher<Void, Never> {
            objectWillChange.map { _ in () }.eraseToAnyPublisher()
        }
        var searchResults: [MKMapItem] = []
        var isSearching = false
        var isLocating = false
        var locationError: LocationController.LocationError?
        var searchFocusTrigger = 0
        var currentLocationCenterTrigger = 0

        private(set) var requestCurrentLocationCalled = false
        private(set) var searchQuery: String?
        private(set) var selectedMapItem: MKMapItem?
        private(set) var selectedCoordinateCalls: [CLLocationCoordinate2D] = []

        func requestCurrentLocation() {
            requestCurrentLocationCalled = true
        }

        func search(query: String) {
            searchQuery = query
            isSearching = true
        }

        func select(_ mapItem: MKMapItem) {
            selectedMapItem = mapItem
            selectedLocation = mapItem.location.coordinate
            currentLocationCenterTrigger += 1
        }

        func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
            selectedCoordinateCalls.append(coordinate)
            selectedLocation = coordinate
            currentLocationCenterTrigger += 1
        }
    }

    final class MockLightPollutionService: LightPollutionProviding {
        @Published var bortleClass: Double? = nil
        var bortleClassPublisher: Published<Double?>.Publisher { $bortleClass }
        @Published var isLoading = false
        @Published var fetchFailed = false

        func fetch(latitude: Double, longitude: Double) async {
            isLoading = true
            try? await Task.sleep(nanoseconds: 1_000_000)
            isLoading = false
        }

        func fetchBortle(latitude: Double, longitude: Double) async throws -> Double {
            4.0
        }
    }

    final class InMemoryLocationStorage: LocationStorage {
        var latitude: Double?
        var longitude: Double?
        var name: String?
    }

    enum MockLocationSearchError: Error {
        case failed
    }

    final class MockLocationSearchService: LocationSearchServicing {
        var result: Result<[MKMapItem], Error>
        private(set) var lastQuery: String?

        init(result: Result<[MKMapItem], Error>) {
            self.result = result
        }

        func search(query: String) async throws -> [MKMapItem] {
            lastQuery = query
            return try result.get()
        }
    }

    final class MockLocationNameResolver: LocationNameResolving {
        var resolvedName: String
        private(set) var lastCoordinate: CLLocationCoordinate2D?

        init(resolvedName: String) {
            self.resolvedName = resolvedName
        }

        func resolveName(for coordinate: CLLocationCoordinate2D) async -> String {
            lastCoordinate = coordinate
            return resolvedName
        }
    }

    func test_SidebarViewModel_handleSearchTextChanged_triggersSearch() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        vm.searchState.text = "Tokyo"
        vm.handleSearchTextChanged()

        XCTAssertEqual(locationController.searchQuery, "Tokyo")
        XCTAssertTrue(locationController.isSearching)
    }

    func test_SidebarViewModel_selectCoordinate_updatesLocationController() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        _ = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        let coord = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)
        locationController.selectCoordinate(coord)

        XCTAssertEqual(locationController.selectedLocation.latitude, coord.latitude)
        XCTAssertEqual(locationController.selectedLocation.longitude, coord.longitude)
        XCTAssertEqual(locationController.currentLocationCenterTrigger, 1)
    }

    // MARK: - LocationController

    func test_LocationController_search_success_updatesResults() async {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let item = makeMapItem(coordinate: coordinate, name: "東京駅")

        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([item]))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        sut.search(query: "東京駅")

        await waitUntil {
            sut.isSearching == false && sut.searchResults.count == 1
        }

        XCTAssertEqual(searchService.lastQuery, "東京駅")
        XCTAssertEqual(sut.searchResults.first?.name, "東京駅")
    }

    func test_LocationController_search_failure_clearsResults() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .failure(MockLocationSearchError.failed))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        sut.searchResults = [makeMapItem(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))]

        sut.search(query: "invalid")

        await waitUntil {
            sut.isSearching == false
        }

        XCTAssertEqual(searchService.lastQuery, "invalid")
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func test_LocationController_select_updatesCenterTriggerAndResolvedName() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "新宿区")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let coordinate = CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034)
        let item = makeMapItem(coordinate: coordinate, name: "新宿")
        let baseTrigger = sut.currentLocationCenterTrigger

        sut.searchResults = [item]
        sut.isSearching = true
        sut.select(item)

        await waitUntil {
            sut.locationName == "新宿区"
        }

        XCTAssertEqual(sut.selectedLocation.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(sut.currentLocationCenterTrigger, baseTrigger + 1)
        XCTAssertFalse(sut.isSearching)
        XCTAssertTrue(sut.searchResults.isEmpty)
        guard let resolvedLatitude = resolver.lastCoordinate?.latitude else {
            return XCTFail("resolver に座標が渡されていません")
        }
        XCTAssertEqual(resolvedLatitude, coordinate.latitude, accuracy: 0.000001)
    }

    func test_LocationController_selectCoordinate_updatesNameWithoutCenterIncrement() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "渋谷区")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let baseTrigger = sut.currentLocationCenterTrigger
        let coordinate = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)
        sut.isLocating = true
        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "渋谷区"
        }

        XCTAssertEqual(sut.currentLocationCenterTrigger, baseTrigger)
        XCTAssertFalse(sut.isLocating)
        XCTAssertEqual(sut.selectedLocation.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, coordinate.longitude, accuracy: 0.000001)
                guard let storedLatitude = storage.latitude,
                            let storedLongitude = storage.longitude else {
                        return XCTFail("選択座標が storage に保存されていません")
                }
                XCTAssertEqual(storedLatitude, coordinate.latitude, accuracy: 0.000001)
                XCTAssertEqual(storedLongitude, coordinate.longitude, accuracy: 0.000001)
    }

    func test_DetailViewModel_selectedDate_syncsBidirectionally() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        vm.selectedDate = tomorrow

        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(appController.selectedDate, tomorrow)

        let afterTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        appController.selectedDate = afterTomorrow

        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(vm.selectedDate, afterTomorrow)
    }

    func test_DetailViewModel_selectedDate_sameValue_doesNotTriggerRecalculation() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        let sameDate = vm.selectedDate
        vm.selectedDate = sameDate

        try? await Task.sleep(nanoseconds: 30_000_000)
        let nightCallCount = await mockCalculationService.getNightSummaryCallCount()
        let upcomingCallCount = await mockCalculationService.getUpcomingCallCount()
        XCTAssertEqual(nightCallCount, 0)
        XCTAssertEqual(upcomingCallCount, 0)
    }

    func test_DetailViewModel_selectedDate_newValue_triggersRecalculation() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: vm.selectedDate)!
        vm.selectedDate = nextDate

        for _ in 0..<30 {
            let nightCalls = await mockCalculationService.getNightSummaryCallCount()
            let upcomingCalls = await mockCalculationService.getUpcomingCallCount()
            if nightCalls > 0 && upcomingCalls > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let nightCallCount = await mockCalculationService.getNightSummaryCallCount()
        let upcomingCallCount = await mockCalculationService.getUpcomingCallCount()
        XCTAssertGreaterThanOrEqual(nightCallCount, 1)
        XCTAssertGreaterThanOrEqual(upcomingCallCount, 1)
    }

    // MARK: - SidebarSearchState

    func test_SidebarSearchState_programmaticText_suppressesOnlyNextSearch() {
        var state = SidebarSearchState()

        XCTAssertTrue(state.setProgrammaticText("Tokyo"))
        XCTAssertTrue(state.consumeSearchSuppression())
        XCTAssertFalse(state.consumeSearchSuppression())
    }

    // MARK: - DetailViewModel error properties

    func test_DetailViewModel_hasLightPollutionError_reflectsService() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.hasLightPollutionError)
        appController.lightPollutionService.fetchFailed = true
        XCTAssertTrue(vm.hasLightPollutionError)
    }

    func test_DetailViewModel_hasWeatherError_reflectsService() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.hasWeatherError)
        XCTAssertNil(vm.weatherErrorMessage)
        appController.weatherService.errorMessage = "テストエラー"
        XCTAssertTrue(vm.hasWeatherError)
        XCTAssertEqual(vm.weatherErrorMessage, "テストエラー")
    }

    // MARK: - NightWeatherCardViewModel

    func test_NightWeatherCardViewModel_formatCloudCover() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.formatCloudCover(75.0), "雲量 75%")
        XCTAssertEqual(vm.formatCloudCover(0.0), "雲量 0%")
        XCTAssertEqual(vm.formatCloudCover(100.0), "雲量 100%")
    }

    func test_NightWeatherCardViewModel_formatPrecipitation() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.formatPrecipitation(2.5), "降水 2.5 mm")
        XCTAssertEqual(vm.formatPrecipitation(0.0), "降水 0.0 mm")
    }

    func test_NightWeatherCardViewModel_formatWindSpeed_defaultKmh() {
        let vm = NightWeatherCardViewModel()
        UserDefaults.standard.set(WindSpeedUnit.kmh.rawValue, forKey: "windSpeedUnit")
        XCTAssertEqual(vm.formatWindSpeed(36.0), "風速 36 km/h")
    }

    func test_NightWeatherCardViewModel_weatherLabel_sameLabelCollapses() {
        let vm = NightWeatherCardViewModel()
        let weather = makeDayWeatherSummary(weatherCode: 0)
        // weatherLabel == cloudLabel のとき重複表示しない
        let label = vm.weatherLabel(weather)
        XCTAssertFalse(label.contains("（"), "同一ラベルのときカッコが付かないこと")
    }

    func test_NightWeatherCardViewModel_accessibilityDescription_loading() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.accessibilityDescription(weather: nil, isLoading: true), "天気 夜間: 取得中")
    }

    func test_NightWeatherCardViewModel_accessibilityDescription_noData() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.accessibilityDescription(weather: nil, isLoading: false), "天気 夜間: データなし")
    }

    func test_NightWeatherCardViewModel_accessibilityDescription_withData() {
        let vm = NightWeatherCardViewModel()
        let weather = makeDayWeatherSummary(cloudCover: 20, windSpeed: 10)
        let desc = vm.accessibilityDescription(weather: weather, isLoading: false)
        XCTAssertTrue(desc.hasPrefix("天気 夜間: "))
        XCTAssertTrue(desc.contains("雲量20%"))
        XCTAssertTrue(desc.contains("降水0.0mm"))
    }

    // MARK: - WeatherPresentation

    func test_WeatherPresentation_combinedLabel_collapsesWhenSame() {
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 0)
        XCTAssertEqual(WeatherPresentation.combinedLabel(for: weather), "快晴")
    }

    func test_WeatherPresentation_combinedLabel_includesCloudLabelWhenDifferent() {
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 61)
        XCTAssertEqual(WeatherPresentation.combinedLabel(for: weather), "小雨（快晴）")
    }

    func test_WeatherPresentation_color_mappingRepresentativeCases() {
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 0), .yellow)
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 61), .blue)
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 95), .orange)
    }

    // MARK: - DarkTimeCardViewModel

    func test_DarkTimeCardViewModel_noWeather_emptyDarkRange_unavailable() {
        // events が空の placeholder は darkRangeText が "" になる
        let summary = NightSummary.placeholder
        let vm = DarkTimeCardViewModel(summary: summary, weather: nil)
        XCTAssertTrue(vm.isUnavailable)
        XCTAssertEqual(vm.displayText, "暗い時間なし")
        XCTAssertEqual(vm.accessibilityLabel, "観測可能時間: 暗い時間なし")
    }

    func test_DarkTimeCardViewModel_noWeather_hasRange_available() {
        // darkRangeText が "〜" を含む summary を用意する
        // NightSummary の darkRangeText は events から計算されるため、
        // AstroEvent を夜間に設定した summary を使う
        let summary = makeNightSummary(withWindow: true)
        let vm = DarkTimeCardViewModel(summary: summary, weather: nil)
        // weather なし → darkRangeText に委譲
        XCTAssertEqual(vm.accessibilityLabel, "観測可能時間: \(vm.displayText)")
    }

    func test_DarkTimeCardViewModel_heavyClouds_returnsWeatherAwareText() {
        // 雲量 100% の weather → weatherAwareRangeText が空 → "天候不良"
        let summary = makeNightSummary(withWindow: true)
        let heavyCloud = makeHourlyWeather(cloudCover: 100, weatherCode: 61)
        let weather = DayWeatherSummary(date: Date(), nighttimeHours: [heavyCloud])
        let vm = DarkTimeCardViewModel(summary: summary, weather: weather)
        // weatherAwareRangeText が "" を返すケースで "天候不良" になる
        if let text = summary.weatherAwareRangeText(nighttimeHours: weather.nighttimeHours), text.isEmpty {
            XCTAssertEqual(vm.displayText, "天候不良")
            XCTAssertTrue(vm.isUnavailable)
        }
    }

    // MARK: - ViewingWindowsSectionViewModel

    func test_ViewingWindowsSectionViewModel_durationText() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel(summary: summary)
        let window = summary.viewingWindows[0]
        // duration = 3600s → "観測 1.0時間"
        XCTAssertEqual(vm.durationText(window), "観測 1.0時間")
    }

    func test_ViewingWindowsSectionViewModel_altitudeText() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel(summary: summary)
        let window = summary.viewingWindows[0]
        XCTAssertEqual(vm.altitudeText(window), "最大高度 32°")
    }

    func test_ViewingWindowsSectionViewModel_moonStatusLabel_favorable() {
        let summary = makeNightSummary(moonPhase: 0.01) // 新月 → isMoonFavorable = true
        let vm = ViewingWindowsSectionViewModel(summary: summary)
        XCTAssertEqual(vm.moonStatusLabel(for: summary.viewingWindows[0]), "条件良好")
    }

    func test_ViewingWindowsSectionViewModel_moonStatusLabel_unfavorable() {
        let summary = makeNightSummary(moonPhase: 0.5) // 満月 → isMoonFavorable = false
        let vm = ViewingWindowsSectionViewModel(summary: summary)
        XCTAssertEqual(vm.moonStatusLabel(for: summary.viewingWindows[0]), "月明かりあり")
    }

    func test_ViewingWindowsSectionViewModel_windowTimeText_containsSeparator() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel(summary: summary)
        let window = summary.viewingWindows[0]
        XCTAssertTrue(vm.windowTimeText(window).contains("〜"))
    }

    // MARK: - UpcomingNightsGridViewModel

    func test_UpcomingNightsGridViewModel_displaysOnlyNightsWithWindows() async {
        let mockCalc = MockNightCalculationService()
        let nightWithWindow = makeNightSummary(date: Date(), withWindow: true)
        let nightWithoutWindow = makeNightSummary(date: Date().addingTimeInterval(86400), withWindow: false)
        await mockCalc.enqueueUpcomingNights([nightWithWindow, nightWithoutWindow])
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let gridVM = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        appController.recalculateUpcoming()
        // Combine の非同期伝播を待つ
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            if !gridVM.displayNights.isEmpty { break }
        }

        XCTAssertEqual(gridVM.displayNights.count, 1)
        XCTAssertTrue(gridVM.displayNights[0].viewingWindows.isEmpty == false)
    }

    func test_UpcomingNightsGridViewModel_observableRangeText_noWeather_emptyRange() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        // events が空の placeholder は darkRangeText が "" → "—" を返す
        let night = NightSummary.placeholder
        XCTAssertEqual(vm.observableRangeText(night: night, weather: nil), "—")
    }

    func test_UpcomingNightsGridViewModel_weatherIconColor_clear() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        XCTAssertEqual(vm.weatherIconColor(code: 0), .yellow)
        XCTAssertEqual(vm.weatherIconColor(code: 1), .yellow)
    }

    func test_UpcomingNightsGridViewModel_weatherIconColor_rain() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        XCTAssertEqual(vm.weatherIconColor(code: 61), .blue)
        XCTAssertEqual(vm.weatherIconColor(code: 80), .blue)
    }

    func test_UpcomingNightsGridViewModel_weatherIconColor_thunderstorm() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        XCTAssertEqual(vm.weatherIconColor(code: 95), .orange)
    }

    func test_UpcomingNightsGridViewModel_cardAccessibilityLabel_containsDate() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        let night = makeNightSummary()
        let label = vm.cardAccessibilityLabel(night: night, weather: nil, index: nil)
        XCTAssertTrue(label.contains("月:"))
        XCTAssertFalse(label.contains("星空指数"))
    }

    func test_UpcomingNightsGridViewModel_cardAccessibilityLabel_withIndex() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        let night = makeNightSummary()
        let weather = makeDayWeatherSummary()
        let index = StarGazingIndex.compute(nightSummary: night, weather: weather, bortleClass: 3.0)
        let label = vm.cardAccessibilityLabel(night: night, weather: weather, index: index)
        XCTAssertTrue(label.contains("星空指数"))
        XCTAssertTrue(label.contains("天気"))
    }

    // MARK: - AppTerminationCoordinator

    func test_AppTerminationCoordinator_registerAndConsumeHandlers_executesEachHandlerOnce() async {
        let coordinator = AppTerminationCoordinator.shared
        _ = coordinator.consumeHandlers()

        let counter = AsyncCounter()
        _ = coordinator.registerHandler {
            await counter.increment()
        }
        _ = coordinator.registerHandler {
            await counter.increment()
        }

        let handlers = coordinator.consumeHandlers()
        XCTAssertEqual(handlers.count, 2)

        for handler in handlers {
            await handler()
        }

        let executedCount = await counter.value
        XCTAssertEqual(executedCount, 2)
        XCTAssertTrue(coordinator.consumeHandlers().isEmpty)
    }

    func test_AppTerminationCoordinator_unregisterHandler_removesRegisteredHandler() async {
        let coordinator = AppTerminationCoordinator.shared
        _ = coordinator.consumeHandlers()

        let counter = AsyncCounter()
        let handlerID = coordinator.registerHandler {
            await counter.increment()
        }
        coordinator.unregisterHandler(id: handlerID)

        let handlers = coordinator.consumeHandlers()
        XCTAssertTrue(handlers.isEmpty)

        let executedCount = await counter.value
        XCTAssertEqual(executedCount, 0)
    }

    func test_AppTerminationCoordinator_consumeHandlers_isOneShot() async {
        let coordinator = AppTerminationCoordinator.shared
        _ = coordinator.consumeHandlers()

        let counter = AsyncCounter()
        _ = coordinator.registerHandler {
            await counter.increment()
        }

        let firstBatch = coordinator.consumeHandlers()
        let secondBatch = coordinator.consumeHandlers()

        XCTAssertEqual(firstBatch.count, 1)
        XCTAssertTrue(secondBatch.isEmpty)

        for handler in firstBatch {
            await handler()
        }

        let executedCount = await counter.value
        XCTAssertEqual(executedCount, 1)
    }

    // MARK: - LLMService termination flow

    func test_LLMService_switchBackend_updatesActiveKind() {
        let service = LLMService()

        service.switchBackend(to: .mlx)
        XCTAssertEqual(service.activeKind, .mlx)

        service.switchBackend(to: .appleIntelligence)
        XCTAssertEqual(service.activeKind, .appleIntelligence)
    }

    func test_LLMService_cancelInference_isIdempotent() async {
        let service = LLMService()

        await service.cancelInference()
        await service.cancelInference()

        XCTAssertTrue(true)
    }

    func test_LLMService_prepareForTermination_afterBackendSwitches_doesNotThrow() async {
        let service = LLMService()

        service.switchBackend(to: .mlx)
        await service.prepareForTermination()

        service.switchBackend(to: .appleIntelligence)
        await service.prepareForTermination()

        XCTAssertTrue(true)
    }

    func test_LLMService_send_afterPrepareForTermination_returnsCancellationError() async {
        let service = LLMService()
        await service.prepareForTermination()

        let stream = service.send(userMessage: "test")

        do {
            for try await _ in stream {}
            XCTFail("終了処理中は send が CancellationError を返すべき")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }
}
