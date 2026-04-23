import XCTest
@testable import NightScope

@MainActor
final class DetailViewModelTests: XCTestCase {
    func test_selectedDate_syncsBidirectionally() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)
        let timeZone = appController.locationController.selectedTimeZone

        let tomorrow = ObservationTimeZone.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            timeZone: timeZone
        )
        vm.selectedDate = tomorrow

        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(appController.selectedDate, tomorrow)

        let afterTomorrow = ObservationTimeZone.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            timeZone: timeZone
        )
        appController.selectedDate = afterTomorrow

        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(vm.selectedDate, afterTomorrow)
    }

    func test_selectedDate_sameValue_doesNotTriggerRecalculation() async {
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

    func test_selectedDate_newValue_triggersSummaryRecalculationOnly() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: vm.selectedDate)!
        vm.selectedDate = nextDate

        for _ in 0..<30 {
            let nightCalls = await mockCalculationService.getNightSummaryCallCount()
            if nightCalls > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let nightCallCount = await mockCalculationService.getNightSummaryCallCount()
        let upcomingCallCount = await mockCalculationService.getUpcomingCallCount()
        XCTAssertGreaterThanOrEqual(nightCallCount, 1)
        XCTAssertEqual(upcomingCallCount, 0)
    }

    func test_hasLightPollutionError_reflectsService() {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.hasLightPollutionError)
        appController.lightPollutionService.fetchFailed = true
        XCTAssertTrue(vm.hasLightPollutionError)
    }

    func test_hasWeatherError_reflectsService() {
        let mockCalculationService = MockNightCalculationService()
        let weatherService = WeatherKitService()
        let appController = AppController(weatherService: weatherService, calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.hasWeatherError)
        XCTAssertNil(vm.weatherErrorMessage)
        weatherService.errorMessage = "テストエラー"
        XCTAssertTrue(vm.hasWeatherError)
        XCTAssertEqual(vm.weatherErrorMessage, "テストエラー")
    }

    func test_currentWeather_tracksWeatherUpdatesForSelectedDate() async {
        let mockCalculationService = MockNightCalculationService()
        let weatherService = WeatherKitService()
        let appController = AppController(weatherService: weatherService, calculationService: mockCalculationService)
        let targetDate = Calendar.current.startOfDay(for: Date())
        let weather = DayWeatherSummary(date: targetDate, nighttimeHours: [makeHourlyWeather(cloudCover: 22)])

        appController.selectedDate = targetDate
        let tz = appController.locationController.selectedTimeZone
        weatherService.weatherByDate = [
            appController.weatherService.dateKey(targetDate, timeZone: tz): weather
        ]
        let vm = DetailViewModel(appController: appController)

        for _ in 0..<30 where vm.currentWeather == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(vm.currentWeather?.avgCloudCover ?? -1, 22, accuracy: 0.001)
    }

    func test_displayedDateAndWeather_stayOnVisibleSummaryWhileRefreshingNextDate() async {
        let mockCalculationService = MockNightCalculationService()
        let weatherService = WeatherKitService()
        let appController = AppController(weatherService: weatherService, calculationService: mockCalculationService)
        let currentDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        let currentSummary = makeNightSummary(date: currentDate)
        let currentWeather = DayWeatherSummary(date: currentDate, nighttimeHours: [makeHourlyWeather(cloudCover: 22)])
        let nextWeather = DayWeatherSummary(date: nextDate, nighttimeHours: [makeHourlyWeather(cloudCover: 88)])

        appController.selectedDate = currentDate
        appController.nightSummary = currentSummary
        let tz1 = appController.locationController.selectedTimeZone
        weatherService.weatherByDate = [
            appController.weatherService.dateKey(currentDate, timeZone: tz1): currentWeather,
            appController.weatherService.dateKey(nextDate, timeZone: tz1): nextWeather
        ]

        let vm = DetailViewModel(appController: appController)

        appController.selectedDate = nextDate
        appController.isCalculating = true

        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(vm.displayedDate, currentDate)
        XCTAssertEqual(vm.currentWeather?.avgCloudCover ?? -1, 22, accuracy: 0.001)
    }

    func test_displayedDateAndWeather_switchToNewSelectionAfterRefreshCompletes() async {
        let mockCalculationService = MockNightCalculationService()
        let weatherService = WeatherKitService()
        let appController = AppController(weatherService: weatherService, calculationService: mockCalculationService)
        let currentDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        let currentSummary = makeNightSummary(date: currentDate)
        let nextSummary = makeNightSummary(date: nextDate)
        let currentWeather = DayWeatherSummary(date: currentDate, nighttimeHours: [makeHourlyWeather(cloudCover: 22)])
        let nextWeather = DayWeatherSummary(date: nextDate, nighttimeHours: [makeHourlyWeather(cloudCover: 88)])

        appController.selectedDate = currentDate
        appController.nightSummary = currentSummary
        let tz2 = appController.locationController.selectedTimeZone
        weatherService.weatherByDate = [
            appController.weatherService.dateKey(currentDate, timeZone: tz2): currentWeather,
            appController.weatherService.dateKey(nextDate, timeZone: tz2): nextWeather
        ]

        let vm = DetailViewModel(appController: appController)

        appController.selectedDate = nextDate
        appController.isCalculating = true
        appController.nightSummary = nextSummary
        appController.isCalculating = false

        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(vm.displayedDate, nextDate)
        XCTAssertEqual(vm.currentWeather?.avgCloudCover ?? -1, 88, accuracy: 0.001)
    }

    func test_nightSummaryAndIndex_stayVisible_whileRecalculatingDifferentDate() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let currentDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        let location = appController.locationController.selectedLocation
        let timeZoneIdentifier = appController.locationController.selectedTimeZone.identifier
        let currentSummary = NightSummary(
            date: currentDate,
            location: location,
            events: makeNightSummary(date: currentDate).events,
            viewingWindows: makeNightSummary(date: currentDate).viewingWindows,
            moonPhaseAtMidnight: 0.12,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let nextSummary = NightSummary(
            date: nextDate,
            location: location,
            events: makeNightSummary(date: nextDate).events,
            viewingWindows: makeNightSummary(date: nextDate).viewingWindows,
            moonPhaseAtMidnight: 0.12,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let currentIndex = StarGazingIndex.compute(
            nightSummary: currentSummary,
            weather: nil,
            bortleClass: 4
        )

        await mockCalculationService.enqueueNightSummary(nextSummary, delayMilliseconds: 250)

        appController.selectedDate = currentDate
        appController.nightSummary = currentSummary
        appController.starGazingIndex = currentIndex

        let vm = DetailViewModel(appController: appController)

        for _ in 0..<30 where vm.nightSummary?.date != currentDate {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        appController.selectObservationDate(nextDate)

        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(vm.isCalculating)
        XCTAssertEqual(vm.nightSummary?.date, currentDate)
        XCTAssertEqual(vm.starGazingIndex?.score, currentIndex.score)
    }

    func test_isWeatherLoading_reflectsService() {
        let mockCalculationService = MockNightCalculationService()
        let weatherService = WeatherKitService()
        let appController = AppController(weatherService: weatherService, calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.isWeatherLoading)
        weatherService.isLoading = true
        XCTAssertTrue(vm.isWeatherLoading)
    }

    func test_isUpcomingLoading_reflectsController() {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        XCTAssertFalse(vm.isUpcomingLoading)
        appController.isUpcomingLoading = true
        XCTAssertTrue(vm.isUpcomingLoading)
    }

    func test_refreshForecast_triggersUpcomingRecalculation() async {
        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let vm = DetailViewModel(appController: appController)

        await vm.refreshForecast()

        for _ in 0..<30 {
            let upcomingCallCount = await mockCalculationService.getUpcomingCallCount()
            if upcomingCallCount > 0 {
                XCTAssertGreaterThanOrEqual(upcomingCallCount, 1)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("予報再計算が開始されませんでした")
    }
}

final class DetailContentStateResolverTests: XCTestCase {
    func test_forecastState_keepsContentWhileRefreshingExistingNights() {
        let resolver = DetailContentStateResolver()

        XCTAssertEqual(
            resolver.forecastState(hasDisplayNights: true, isUpcomingLoading: true),
            .content
        )
    }
}

@MainActor
final class NightWeatherCardViewModelTests: XCTestCase {
    func test_formatCloudCover() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.formatCloudCover(75.0), L10n.format("weather.cloudCover.label", L10n.percent(75.0)))
        XCTAssertEqual(vm.formatCloudCover(0.0), L10n.format("weather.cloudCover.label", L10n.percent(0.0)))
        XCTAssertEqual(vm.formatCloudCover(100.0), L10n.format("weather.cloudCover.label", L10n.percent(100.0)))
    }

    func test_formatPrecipitation() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(vm.formatPrecipitation(2.5), L10n.format("降水 %.1f mm", 2.5))
        XCTAssertEqual(vm.formatPrecipitation(0.0), L10n.format("降水 %.1f mm", 0.0))
    }

    func test_formatMetrics() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(
            vm.formatMetrics(precipitation: 2.5, cloudCover: 75.0),
            "\(vm.formatPrecipitation(2.5)) ・ \(vm.formatCloudCover(75.0))"
        )
    }

    func test_formatWindSpeed_defaultKmh() {
        let vm = NightWeatherCardViewModel()
        UserDefaults.standard.set(WindSpeedUnit.kmh.rawValue, forKey: "windSpeedUnit")
        XCTAssertEqual(vm.formatWindSpeed(36.0), WindSpeedUnit.kmh.format(36.0))
    }

    func test_weatherLabel_usesPrimaryForecast() {
        let vm = NightWeatherCardViewModel()
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 61)
        XCTAssertEqual(vm.weatherLabel(weather), L10n.tr("小雨"))
    }

    func test_accessibilityDescription_loading() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(
            vm.accessibilityDescription(
                weather: nil,
                isLoading: true,
                isForecastOutOfRange: false,
                isCoverageIncomplete: false
            ),
            L10n.tr("天気 夜間: 取得中")
        )
    }

    func test_accessibilityDescription_noData() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(
            vm.accessibilityDescription(
                weather: nil,
                isLoading: false,
                isForecastOutOfRange: false,
                isCoverageIncomplete: false
            ),
            L10n.tr("天気 夜間: 不明、データなし、10日以内のみ")
        )
    }

    func test_accessibilityDescription_partialCoverage() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(
            vm.accessibilityDescription(
                weather: makeDayWeatherSummary(),
                isLoading: false,
                isForecastOutOfRange: false,
                isCoverageIncomplete: true
            ),
            L10n.tr("天気 夜間: 予報一部のみ、夜間を最後まで評価できません、星空指数には反映していません")
        )
    }

    func test_accessibilityDescription_forecastOutOfRange() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(
            vm.accessibilityDescription(
                weather: nil,
                isLoading: false,
                isForecastOutOfRange: true,
                isCoverageIncomplete: false
            ),
            L10n.tr("天気 夜間: 予報対象外、この日は天気予報の対象外です、天文情報のみ表示しています")
        )
    }

    func test_accessibilityDescription_error() {
        let vm = NightWeatherCardViewModel()
        XCTAssertEqual(
            vm.accessibilityDescription(
                weather: nil,
                isLoading: false,
                isForecastOutOfRange: false,
                isCoverageIncomplete: false,
                errorMessage: "通信に失敗しました"
            ),
            L10n.format("天気 夜間: 取得失敗、%@、再試行してください", "通信に失敗しました")
        )
    }

    func test_accessibilityDescription_withData() {
        let vm = NightWeatherCardViewModel()
        let weather = makeDayWeatherSummary(cloudCover: 20, windSpeed: 10)
        let desc = vm.accessibilityDescription(
            weather: weather,
            isLoading: false,
            isForecastOutOfRange: false,
            isCoverageIncomplete: false
        )
        XCTAssertEqual(
            desc,
            L10n.format(
                "weather.night.accessibility.metrics",
                vm.weatherLabel(weather),
                L10n.format("weather.precipitation.compact", L10n.number(weather.maxPrecipitation, fractionDigits: 1)),
                L10n.format("weather.cloudCover.compact", L10n.percent(weather.avgCloudCover)),
                vm.formatWindSpeed(weather.avgWindSpeed)
            )
        )
    }
}

final class WeatherPresentationTests: XCTestCase {
    func test_primaryLabel_returnsForecast() {
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 0)
        XCTAssertEqual(WeatherPresentation.primaryLabel(for: weather), L10n.tr("快晴"))
    }

    func test_primaryLabel_ignoresCloudLabel() {
        let weather = makeDayWeatherSummary(cloudCover: 0, weatherCode: 61)
        XCTAssertEqual(WeatherPresentation.primaryLabel(for: weather), L10n.tr("小雨"))
    }

    func test_color_mappingRepresentativeCases() {
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 0), .yellow)
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 61), .blue)
        XCTAssertEqual(WeatherPresentation.color(forWeatherCode: 95), .orange)
    }
}

final class ForecastCardPresentationTests: XCTestCase {
    func test_weatherDetailText_usesWeatherLabelForReliableForecast() {
        let night = makeNightSummary()
        let weather = makeDayWeatherSummary(cloudCover: 18, weatherCode: 61)
        let sut = ForecastCardPresentation(
            night: night,
            weather: weather,
            timeZone: night.timeZone,
            isReliableWeather: true,
            hasPartialWeather: false,
            isForecastOutOfRange: false,
            hasWeatherLoadError: false
        )

        XCTAssertEqual(sut.weatherDetailText, L10n.tr("小雨"))
    }

    func test_weatherDetailText_returnsPartialMessageWhenCoverageIsIncomplete() {
        let night = makeNightSummary()
        let sut = ForecastCardPresentation(
            night: night,
            weather: nil,
            timeZone: night.timeZone,
            isReliableWeather: false,
            hasPartialWeather: true,
            isForecastOutOfRange: false,
            hasWeatherLoadError: false
        )

        XCTAssertEqual(sut.weatherDetailText, L10n.tr("夜間予報は一部のみ"))
    }

    func test_weatherDetailText_returnsFailureMessageWhenLoadFailed() {
        let night = makeNightSummary()
        let sut = ForecastCardPresentation(
            night: night,
            weather: nil,
            timeZone: night.timeZone,
            isReliableWeather: false,
            hasPartialWeather: false,
            isForecastOutOfRange: false,
            hasWeatherLoadError: true
        )

        XCTAssertEqual(sut.weatherDetailText, L10n.tr("取得失敗"))
    }
}

@MainActor
final class DarkTimeCardViewModelTests: XCTestCase {
    func test_noWeather_emptyDarkRange_unavailable() {
        let summary = NightSummary.placeholder
        let vm = DarkTimeCardViewModel(summary: summary, weather: nil)
        XCTAssertTrue(vm.isUnavailable)
        XCTAssertEqual(vm.displayText, L10n.tr("暗い時間なし"))
        XCTAssertEqual(vm.accessibilityLabel, L10n.format("観測可能時間: %@", vm.displayText))
    }

    func test_noWeather_hasRange_available() {
        let summary = makeNightSummary(withWindow: true)
        let vm = DarkTimeCardViewModel(summary: summary, weather: nil)
        XCTAssertEqual(vm.accessibilityLabel, L10n.format("観測可能時間: %@", vm.displayText))
    }

    func test_heavyClouds_returnsWeatherAwareText() {
        let summary = makeNightSummary(withWindow: true)
        let heavyCloud = makeHourlyWeather(cloudCover: 100, weatherCode: 61)
        let weather = DayWeatherSummary(date: Date(), nighttimeHours: [heavyCloud])
        let vm = DarkTimeCardViewModel(summary: summary, weather: weather)
        if let text = summary.weatherAwareRangeText(nighttimeHours: weather.nighttimeHours), text.isEmpty {
            XCTAssertEqual(vm.displayText, L10n.tr("天候不良"))
            XCTAssertTrue(vm.isUnavailable)
        }
    }
}

@MainActor
final class ViewingWindowsSectionViewModelTests: XCTestCase {
    func test_altitudeText() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        XCTAssertEqual(vm.altitudeText(window), L10n.format("最大高度 %.0f°", window.peakAltitude))
    }

    func test_windowTimeText_containsSeparator() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        XCTAssertTrue(vm.windowTimeText(window, timeZone: summary.timeZone).contains("〜"))
    }

    func test_timeAndPeakText_includesPeakTime() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        let text = vm.timeAndPeakText(window, timeZone: summary.timeZone)

        XCTAssertEqual(text, "\(vm.windowTimeText(window, timeZone: summary.timeZone)) \(vm.peakTimeText(window, timeZone: summary.timeZone))")
    }

    func test_directionText() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]

        XCTAssertEqual(vm.directionText(window), L10n.format("方位 %@", window.peakDirectionName))
    }

    func test_accessibilityDescription_excludesRemovedFields() {
        let summary = makeNightSummary(withWindow: true)
        let vm = ViewingWindowsSectionViewModel()
        let window = summary.viewingWindows[0]
        let description = vm.accessibilityDescription(for: window, timeZone: summary.timeZone)
        XCTAssertEqual(description, window.accessibilityDescription(timeZone: summary.timeZone))
        XCTAssertFalse(description.contains("観測 1.0時間"))
        XCTAssertFalse(description.contains("条件良好"))
        XCTAssertFalse(description.contains("月明かりあり"))
    }
}
