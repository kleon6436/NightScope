import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class ViewModelTests: XCTestCase {

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

    private func makeDayWeatherSummary(cloudCover: Double = 10, weatherCode: Int = 0, windSpeed: Double = 5) -> DayWeatherSummary {
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

    // MARK: - Shared Mocks

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
        var isLoadingPublisher: Published<Bool>.Publisher { $isLoading }
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

    // MARK: - SidebarViewModel

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

    func test_AppRootDependencies_makeDefault_sharesControllerDependencies() {
        let dependencies = AppRootDependencies.makeDefault()

        XCTAssertTrue((dependencies.sidebarViewModel.locationController as AnyObject) === dependencies.appController.locationController)
        XCTAssertTrue(dependencies.detailViewModel.weatherService === dependencies.appController.weatherService)
        XCTAssertTrue(dependencies.detailViewModel.lightPollutionService === dependencies.appController.lightPollutionService)
    }

    // MARK: - DetailViewModel

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

    func test_DetailViewModel_currentWeather_tracksWeatherUpdatesForSelectedDate() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let targetDate = Calendar.current.startOfDay(for: Date())
        let weather = DayWeatherSummary(date: targetDate, nighttimeHours: [makeHourlyWeather(cloudCover: 22)])

        appController.selectedDate = targetDate
        appController.weatherService.weatherByDate = [
            appController.weatherService.dateKey(targetDate): weather
        ]
        let vm = DetailViewModel(appController: appController)

        for _ in 0..<30 where vm.currentWeather == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(vm.currentWeather?.avgCloudCover ?? -1, 22, accuracy: 0.001)
    }

    func test_DetailViewModel_isWeatherLoading_reflectsService() {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.isWeatherLoading)
        appController.weatherService.isLoading = true
        XCTAssertTrue(vm.isWeatherLoading)
    }

    func test_DetailViewModel_isUpcomingLoading_reflectsController() {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.isUpcomingLoading)
        appController.isUpcomingLoading = true
        XCTAssertTrue(vm.isUpcomingLoading)
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

    func test_NightWeatherCardViewModel_formatMetrics() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.formatMetrics(precipitation: 2.5, cloudCover: 75.0), "降水 2.5 mm ・ 雲量 75%")
    }

    func test_NightWeatherCardViewModel_formatWindSpeed_defaultKmh() {
        let vm = NightWeatherCardViewModel()
        UserDefaults.standard.set(WindSpeedUnit.kmh.rawValue, forKey: "windSpeedUnit")
        XCTAssertEqual(vm.formatWindSpeed(36.0), "風速 36 km/h")
    }

    func test_NightWeatherCardViewModel_weatherLabel_usesPrimaryForecast() {
        let vm = NightWeatherCardViewModel()
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 61)
        XCTAssertEqual(vm.weatherLabel(weather), "小雨")
    }

    func test_NightWeatherCardViewModel_accessibilityDescription_loading() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.accessibilityDescription(weather: nil, isLoading: true), "天気 夜間: 取得中")
    }

    func test_NightWeatherCardViewModel_accessibilityDescription_noData() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.accessibilityDescription(weather: nil, isLoading: false), "天気 夜間: 不明、データなし、10日以内のみ")
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

    func test_WeatherPresentation_primaryLabel_returnsForecast() {
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 0)
        XCTAssertEqual(WeatherPresentation.primaryLabel(for: weather), "快晴")
    }

    func test_WeatherPresentation_primaryLabel_ignoresCloudLabel() {
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 61)
        XCTAssertEqual(WeatherPresentation.primaryLabel(for: weather), "小雨")
    }

    func test_WeatherPresentation_color_mappingRepresentativeCases() {
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 0), .yellow)
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 61), .blue)
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 95), .orange)
    }

    // MARK: - DarkTimeCardViewModel

    func test_DarkTimeCardViewModel_noWeather_emptyDarkRange_unavailable() {
        let summary = NightSummary.placeholder
        let vm = DarkTimeCardViewModel(summary: summary, weather: nil)
        XCTAssertTrue(vm.isUnavailable)
        XCTAssertEqual(vm.displayText, "暗い時間なし")
        XCTAssertEqual(vm.accessibilityLabel, "観測可能時間: 暗い時間なし")
    }

    func test_DarkTimeCardViewModel_noWeather_hasRange_available() {
        let summary = makeNightSummary(withWindow: true)
        let vm = DarkTimeCardViewModel(summary: summary, weather: nil)
        XCTAssertEqual(vm.accessibilityLabel, "観測可能時間: \(vm.displayText)")
    }

    func test_DarkTimeCardViewModel_heavyClouds_returnsWeatherAwareText() {
        let summary = makeNightSummary(withWindow: true)
        let heavyCloud = makeHourlyWeather(cloudCover: 100, weatherCode: 61)
        let weather = DayWeatherSummary(date: Date(), nighttimeHours: [heavyCloud])
        let vm = DarkTimeCardViewModel(summary: summary, weather: weather)
        if let text = summary.weatherAwareRangeText(nighttimeHours: weather.nighttimeHours), text.isEmpty {
            XCTAssertEqual(vm.displayText, "天候不良")
            XCTAssertTrue(vm.isUnavailable)
        }
    }

    // MARK: - ViewingWindowsSectionViewModel

    func test_ViewingWindowsSectionViewModel_altitudeText() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        XCTAssertEqual(vm.altitudeText(window), "最大高度 32°")
    }

    func test_ViewingWindowsSectionViewModel_windowTimeText_containsSeparator() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        XCTAssertTrue(vm.windowTimeText(window).contains("〜"))
    }

    func test_ViewingWindowsSectionViewModel_timeAndPeakText_includesPeakTime() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        let text = vm.timeAndPeakText(window)

        XCTAssertTrue(text.contains("〜"))
        XCTAssertTrue(text.contains("見頃"))
        XCTAssertTrue(text.contains(window.peakTime.nightTimeString()))
    }

    func test_ViewingWindowsSectionViewModel_directionText() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]

        XCTAssertEqual(vm.directionText(window), "方位 南")
    }

    func test_ViewingWindowsSectionViewModel_accessibilityDescription_excludesRemovedFields() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        let description = vm.accessibilityDescription(for: window)
        XCTAssertTrue(description.contains("観測窓:"))
        XCTAssertTrue(description.contains("最大高度32度"))
        XCTAssertTrue(description.contains("見頃"))
        XCTAssertTrue(description.contains("方角"))
        XCTAssertFalse(description.contains("観測 1.0時間"))
        XCTAssertFalse(description.contains("条件良好"))
        XCTAssertFalse(description.contains("月明かりあり"))
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
}
