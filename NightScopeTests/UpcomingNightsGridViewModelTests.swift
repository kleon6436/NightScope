import XCTest
@testable import NightScope

@MainActor
final class UpcomingNightsGridViewModelTests: XCTestCase {
    func test_displaysAllUpcomingNights() async {
        let mockCalc = MockNightCalculationService()
        let nightWithWindow = makeNightSummary(date: Date(), withWindow: true)
        let nightWithoutWindow = makeNightSummary(date: Date().addingTimeInterval(86_400), withWindow: false)
        await mockCalc.enqueueUpcomingNights([nightWithWindow, nightWithoutWindow])
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let gridVM = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        appController.recalculateUpcoming()
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            if !gridVM.displayNights.isEmpty { break }
        }

        XCTAssertEqual(gridVM.displayNights.count, 2)
        XCTAssertFalse(gridVM.displayNights[0].viewingWindows.isEmpty)
        XCTAssertTrue(gridVM.displayNights[1].viewingWindows.isEmpty)
    }

    func test_observableRangeText_noWeather_emptyRange() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        // placeholder は events=[] → totalDarkHours=0 → "暗い時間なし"
        XCTAssertEqual(vm.observableRangeText(night: .placeholder, weather: nil), L10n.tr("暗い時間なし"))
    }

    func test_weatherIconColor_clear() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        XCTAssertEqual(vm.weatherIconColor(code: 0), .yellow)
        XCTAssertEqual(vm.weatherIconColor(code: 1), .yellow)
    }

    func test_weatherIconColor_rain() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        XCTAssertEqual(vm.weatherIconColor(code: 61), .blue)
        XCTAssertEqual(vm.weatherIconColor(code: 80), .blue)
    }

    func test_weatherIconColor_thunderstorm() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        XCTAssertEqual(vm.weatherIconColor(code: 95), .orange)
    }

    func test_cardAccessibilityLabel_containsDate() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        let night = makeNightSummary()
        let label = vm.cardAccessibilityLabel(night: night, weather: nil, index: nil)
        XCTAssertTrue(label.contains(DateFormatters.fullDateString(from: night.date, timeZone: detailVM.selectedTimeZone)))
        XCTAssertTrue(label.contains(L10n.format("月: %@", night.moonPhaseName)))
    }

    func test_cardAccessibilityLabel_withIndex() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        let night = makeNightSummary()
        let weather = DayWeatherSummary(date: night.date, nighttimeHours: [
            HourlyWeather(
                date: night.events[0].date,
                temperatureCelsius: 15,
                cloudCoverPercent: 10,
                precipitationMM: 0,
                windSpeedKmh: 5,
                humidityPercent: 40,
                dewpointCelsius: 2,
                weatherCode: 0,
                visibilityMeters: 20_000,
                windGustsKmh: nil,
                windSpeedKmh500hpa: nil
            )
        ])
        let index = StarGazingIndex.compute(nightSummary: night, weather: weather, bortleClass: 3.0)
        let label = vm.cardAccessibilityLabel(night: night, weather: weather, index: index)
        XCTAssertTrue(label.contains(L10n.format("星空指数%d", index.score)))
        XCTAssertTrue(label.contains(L10n.format("天気%@", weather.weatherLabel)))
    }

    func test_cardAccessibilityLabel_withPartialWeather_usesPartialForecastMessage() {
        let mockCalc = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalc)
        let detailVM = DetailViewModel(appController: appController)
        let vm = UpcomingNightsGridViewModel(detailViewModel: detailVM)

        let night = makeNightSummary(withWindow: true)
        let weather = DayWeatherSummary(date: night.date, nighttimeHours: [
            makeHourlyWeather()
        ])
        let label = vm.cardAccessibilityLabel(night: night, weather: weather, index: nil)

        XCTAssertTrue(label.contains(L10n.tr("天気予報一部のみ")))
        XCTAssertFalse(label.contains(L10n.format("天気%@", weather.weatherLabel)))
    }
}
