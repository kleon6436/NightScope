import XCTest
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class AppControllerTests: XCTestCase {
    final class InMemoryLocationStorage: LocationStorage {
        var latitude: Double?
        var longitude: Double?
        var name: String?
        var timeZoneIdentifier: String?
    }

    actor NoopLocationSearchService: LocationSearchServicing {
        func search(query: String) async throws -> [MKMapItem] { [] }
    }

    actor FixedLocationNameResolver: LocationNameResolving {
        let details: ResolvedLocationDetails

        init(details: ResolvedLocationDetails) {
            self.details = details
        }

        func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails {
            details
        }
    }

    final class CalculationInvocationRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var invokedDates: [Date] = []

        func record(_ date: Date) {
            lock.lock()
            invokedDates.append(date)
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return invokedDates.count
        }
    }

    actor RequestedDaysNightCalculationService: NightCalculating {
        private var requestedUpcomingDays: [Int] = []

        func calculateNightSummary(
            date: Date,
            location: CLLocationCoordinate2D,
            timeZone: TimeZone
        ) async -> NightSummary {
            Self.makeNightSummary(date: date, location: location, timeZone: timeZone)
        }

        func calculateUpcomingNights(
            from date: Date,
            location: CLLocationCoordinate2D,
            timeZone: TimeZone,
            days: Int
        ) async -> [NightSummary] {
            requestedUpcomingDays.append(days)
            let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
            let startDate = calendar.startOfDay(for: date)
            return (0..<days).map { offset in
                let targetDate = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
                return Self.makeNightSummary(date: targetDate, location: location, timeZone: timeZone)
            }
        }

        func lastRequestedUpcomingDays() -> Int? {
            requestedUpcomingDays.last
        }

        private static func makeNightSummary(
            date: Date,
            location: CLLocationCoordinate2D,
            timeZone: TimeZone
        ) -> NightSummary {
            let eventDate = ObservationTimeZone.gregorianCalendar(timeZone: timeZone).date(
                byAdding: .hour,
                value: 21,
                to: date
            ) ?? date
            let event = AstroEvent(
                date: eventDate,
                galacticCenterAltitude: 28,
                galacticCenterAzimuth: 190,
                sunAltitude: -22,
                moonAltitude: -8,
                moonPhase: 0.12
            )
            let window = ViewingWindow(
                start: eventDate,
                end: eventDate.addingTimeInterval(90 * 60),
                peakTime: eventDate.addingTimeInterval(45 * 60),
                peakAltitude: 32,
                peakAzimuth: 200
            )
            return NightSummary(
                date: date,
                location: location,
                events: [event],
                viewingWindows: [window],
                moonPhaseAtMidnight: 0.12,
                timeZoneIdentifier: timeZone.identifier
            )
        }
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_init_usesLaunchDateAndIgnoresPersistedSelectedDate() {
        let key = "selectedDate"
        let userDefaults = UserDefaults.standard
        let originalValue = userDefaults.object(forKey: key)
        let sentinelDate = Date(timeIntervalSince1970: 123_456_789)
        userDefaults.set(sentinelDate.timeIntervalSince1970, forKey: key)
        defer {
            if let originalValue {
                userDefaults.set(originalValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }

        let storage = InMemoryLocationStorage()
        storage.timeZoneIdentifier = TimeZone.current.identifier
        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                details: ResolvedLocationDetails(name: "東京", timeZoneIdentifier: TimeZone.current.identifier)
            )
        )
        let appController = AppController(
            locationController: locationController,
            calculationService: MockNightCalculationService()
        )
        let selectedTimeZone = locationController.selectedTimeZone

        XCTAssertTrue(ObservationTimeZone.isDateInToday(appController.selectedDate, timeZone: selectedTimeZone))
        XCTAssertFalse(ObservationTimeZone.isDate(
            appController.selectedDate,
            inSameDayAs: sentinelDate,
            timeZone: selectedTimeZone
        ))
        XCTAssertEqual(userDefaults.double(forKey: key), sentinelDate.timeIntervalSince1970)
    }

    private func makeNightSummary(
        date: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> NightSummary {
        let location = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let eventDate = Calendar.current.date(byAdding: .hour, value: 21, to: date) ?? date
        let event = AstroEvent(
            date: eventDate,
            galacticCenterAltitude: 28,
            galacticCenterAzimuth: 190,
            sunAltitude: -22,
            moonAltitude: -8,
            moonPhase: 0.12
        )
        let window = ViewingWindow(
            start: eventDate,
            end: eventDate.addingTimeInterval(90 * 60),
            peakTime: eventDate.addingTimeInterval(45 * 60),
            peakAltitude: 32,
            peakAzimuth: 200
        )
        return NightSummary(
            date: date,
            location: location,
            events: [event],
            viewingWindows: [window],
            moonPhaseAtMidnight: 0.12,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func makeWeatherSummary(date: Date) -> DayWeatherSummary {
        let eventDate = Calendar.current.date(byAdding: .hour, value: 21, to: date) ?? date
        let hourStart = Calendar.current.dateInterval(of: .hour, for: eventDate)?.start ?? eventDate
        let hourly = HourlyWeather(
            date: hourStart,
            temperatureCelsius: 12,
            cloudCoverPercent: 15,
            precipitationMM: 0,
            windSpeedKmh: 5,
            humidityPercent: 40,
            dewpointCelsius: 2,
            weatherCode: 0,
            visibilityMeters: 20000,
            windGustsKmh: 10,
            windSpeedKmh500hpa: 20
        )
        return DayWeatherSummary(date: date, nighttimeHours: [hourly])
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

    private func makeMockWeatherService(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> WeatherService {
        MockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return WeatherService(urlSession: URLSession(configuration: configuration))
    }

    private func makeTwoByTwoLightPollutionGrid(
        southWestBrightness: Double = 0.001,
        southEastBrightness: Double = 0.001,
        northWestBrightness: Double,
        northEastBrightness: Double
    ) -> BortleGridData? {
        var data = Data()
        data.append(contentsOf: [0x42, 0x4F, 0x52, 0x54])

        var version = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latCells = Int32(2).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latCells) { Array($0) })

        var lonCells = Int32(2).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &lonCells) { Array($0) })

        for brightness in [
            Float(southWestBrightness),
            Float(southEastBrightness),
            Float(northWestBrightness),
            Float(northEastBrightness)
        ] {
            var value = brightness.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
        }

        return BortleGridData(data: data)
    }

    func test_recalculate_latestTaskWinsAfterCancellation() async {
        let calendar = Calendar.current
        let firstDate = calendar.startOfDay(for: Date())
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate) ?? firstDate

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: firstDate), delayMilliseconds: 250)
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: secondDate), delayMilliseconds: 0)

        let appController = AppController(calculationService: mockCalculationService)

        appController.selectedDate = firstDate
        appController.recalculate()

        appController.selectedDate = secondDate
        appController.recalculate()

        await waitUntil {
            appController.nightSummary?.date == secondDate && appController.isCalculating == false
        }

        // 先行タスクが遅れて戻ってきても上書きされないことを確認
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(appController.nightSummary?.date, secondDate)
    }

    func test_recalculateUpcoming_buildsIndexesForAllNights() async {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())
        let nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueUpcomingNights([
            makeNightSummary(date: baseDate),
            makeNightSummary(date: nextDate)
        ])

        let appController = AppController(calculationService: mockCalculationService)
        appController.recalculateUpcoming()

        await waitUntil {
            appController.upcomingNights.count == 2 && appController.upcomingIndexes.count == 2
        }

        XCTAssertEqual(appController.upcomingIndexes.count, 2)
    }

    func test_weatherPublisherUpdate_recomputesUpcomingIndexes() async {
        let baseDate = Calendar.current.startOfDay(for: Date())
        let night = makeNightSummary(date: baseDate)

        let mockCalculationService = MockNightCalculationService()
        let appController = AppController(calculationService: mockCalculationService)
        let selectedTimeZone = appController.locationController.selectedTimeZone

        appController.upcomingNights = [night]
        appController.recomputeUpcomingIndexes()

        let dayKey = ObservationTimeZone.startOfDay(for: night.date, timeZone: selectedTimeZone)
        XCTAssertEqual(appController.upcomingIndexes[dayKey]?.hasWeatherData, false)

        let weatherSummary = makeWeatherSummary(date: night.date)
        appController.weatherService.weatherByDate = [
            appController.weatherService.dateKey(night.date, timeZone: selectedTimeZone): weatherSummary
        ]

        await waitUntil {
            appController.upcomingIndexes[dayKey]?.hasWeatherData == true
        }

        XCTAssertEqual(appController.upcomingIndexes[dayKey]?.hasWeatherData, true)
    }

    func test_refreshExternalData_skipsStaleLightPollutionAfterLocationChangesMidRefresh() async {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let losAngeles = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let storage = InMemoryLocationStorage()
        storage.latitude = tokyo.latitude
        storage.longitude = tokyo.longitude
        storage.name = "東京"
        storage.timeZoneIdentifier = "Asia/Tokyo"

        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                details: ResolvedLocationDetails(name: "東京", timeZoneIdentifier: "Asia/Tokyo")
            )
        )
        let weatherService = makeMockWeatherService { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let latitude = components.queryItems?.first(where: { $0.name == "lat" })?.value
            let longitude = components.queryItems?.first(where: { $0.name == "lon" })?.value

            XCTAssertEqual(latitude, "35.6762")
            XCTAssertEqual(longitude, "139.6503")

            Thread.sleep(forTimeInterval: 0.2)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data(#"{"properties":{"timeseries":[]}}"#.utf8))
        }
        let grid = makeTwoByTwoLightPollutionGrid(
            northWestBrightness: 0.0172,
            northEastBrightness: 0.172
        )
        let lightPollutionService = LightPollutionService(gridData: grid)
        let appController = AppController(
            locationController: locationController,
            weatherService: weatherService,
            lightPollutionService: lightPollutionService,
            calculationService: MockNightCalculationService()
        )

        let refreshTask = Task {
            await appController.refreshExternalData()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        locationController.selectedLocation = losAngeles
        await refreshTask.value

        XCTAssertNil(appController.lightPollutionService.bortleClass)
    }

    func test_locationChange_keepsNineUpcomingNights() async {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let losAngeles = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo")!
        let losAngelesTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let storage = InMemoryLocationStorage()
        storage.latitude = tokyo.latitude
        storage.longitude = tokyo.longitude
        storage.name = "東京"
        storage.timeZoneIdentifier = tokyoTimeZone.identifier

        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                details: ResolvedLocationDetails(name: "ロサンゼルス", timeZoneIdentifier: losAngelesTimeZone.identifier)
            )
        )
        let calculationService = RequestedDaysNightCalculationService()
        let weatherService = makeMockWeatherService { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data(#"{"properties":{"timeseries":[]}}"#.utf8))
        }
        let lightPollutionService = LightPollutionService(
            gridData: makeTwoByTwoLightPollutionGrid(
                northWestBrightness: 0.0172,
                northEastBrightness: 0.172
            )
        )
        let appController = AppController(
            locationController: locationController,
            weatherService: weatherService,
            lightPollutionService: lightPollutionService,
            calculationService: calculationService
        )

        locationController.selectCoordinate(losAngeles)

        await waitUntil(timeout: 2.0) {
            locationController.selectedTimeZone.identifier == losAngelesTimeZone.identifier
                && appController.isUpcomingLoading == false
                && appController.upcomingNights.count == 9
        }

        let requestedUpcomingDays = await calculationService.lastRequestedUpcomingDays()
        XCTAssertEqual(requestedUpcomingDays, 9)
        XCTAssertEqual(appController.upcomingNights.count, 9)
        XCTAssertEqual(appController.upcomingIndexes.count, 9)
    }

    func test_makeStarGazingIndex_usesProvidedWeatherSnapshotAndTimeZone() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDate = utcCalendar.date(from: DateComponents(
            year: 2024,
            month: 3,
            day: 10,
            hour: 7,
            minute: 30
        ))!
        let night = makeNightSummary(date: selectedDate, timeZoneIdentifier: losAngeles.identifier)
        let weather = makeWeatherSummary(date: selectedDate)
        let snapshot = [
            appController.weatherService.dateKey(selectedDate, timeZone: losAngeles): weather
        ]

        appController.weatherService.weatherByDate = [:]

        let index = appController.makeStarGazingIndex(
            nightSummary: night,
            weatherByDate: snapshot,
            bortleClass: 4
        )

        XCTAssertTrue(index.hasWeatherData)
        XCTAssertGreaterThan(index.score, 0)
        XCTAssertNil(appController.weatherService.summary(for: selectedDate, from: snapshot, timeZone: tokyo))
    }

    func test_makeUpcomingIndexes_usesProvidedWeatherSnapshotAndTimeZone() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseDate = utcCalendar.date(from: DateComponents(
            year: 2024,
            month: 3,
            day: 10,
            hour: 7,
            minute: 30
        ))!
        let nextDate = baseDate.addingTimeInterval(86_400)
        let firstNight = makeNightSummary(date: baseDate)
        let secondNight = makeNightSummary(date: nextDate)
        let firstWeather = makeWeatherSummary(date: baseDate)
        let secondWeather = makeWeatherSummary(date: nextDate)
        let snapshot = [
            appController.weatherService.dateKey(baseDate, timeZone: losAngeles): firstWeather,
            appController.weatherService.dateKey(nextDate, timeZone: losAngeles): secondWeather
        ]

        let indexes = appController.makeUpcomingIndexes(
            upcomingNights: [firstNight, secondNight],
            weatherByDate: snapshot,
            bortleClass: 4,
            timeZone: losAngeles
        )

        XCTAssertEqual(indexes.count, 2)
        XCTAssertTrue(indexes.values.allSatisfy(\.hasWeatherData))
    }

    func test_recomputeStarGazingIndex_usesNightSummaryDateWhileSelectionIsChanging() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let calendar = Calendar(identifier: .gregorian)
        let currentDate = calendar.startOfDay(for: Date())
        let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        let summary = makeNightSummary(date: currentDate)
        let nextWeather = makeWeatherSummary(date: nextDate)

        appController.nightSummary = summary
        appController.selectedDate = nextDate
        appController.weatherService.weatherByDate = [
            appController.weatherService.dateKey(nextDate): nextWeather
        ]

        appController.recomputeStarGazingIndex()

        XCTAssertFalse(appController.starGazingIndex?.hasWeatherData ?? true)
    }

    func test_recalculate_clearsDisplayedNightSummaryUntilNewDateCompletes() async {
        let baseDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let oldSummary = makeNightSummary(date: baseDate)
        let oldIndex = StarGazingIndex.compute(
            nightSummary: oldSummary,
            weather: nil,
            bortleClass: 4
        )

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: nextDate), delayMilliseconds: 250)

        let appController = AppController(calculationService: mockCalculationService)
        appController.nightSummary = oldSummary
        appController.starGazingIndex = oldIndex
        appController.selectedDate = nextDate

        appController.recalculate()

        XCTAssertNil(appController.nightSummary)
        XCTAssertNil(appController.starGazingIndex)
        XCTAssertTrue(appController.isCalculating)
    }

    func test_handleSceneDidBecomeActive_advancesSelectedDateWhenTrackingTodayAcrossDayBoundary() async {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let storage = InMemoryLocationStorage()
        storage.timeZoneIdentifier = tokyo.identifier
        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                details: ResolvedLocationDetails(name: "東京", timeZoneIdentifier: tokyo.identifier)
            )
        )
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: tokyo)
        let firstActiveDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 21))!
        let secondActiveDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 7))!
        let firstDay = ObservationTimeZone.startOfDay(for: firstActiveDate, timeZone: tokyo)
        let secondDay = ObservationTimeZone.startOfDay(for: secondActiveDate, timeZone: tokyo)

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: firstDay, timeZoneIdentifier: tokyo.identifier))
        await mockCalculationService.enqueueUpcomingNights([makeNightSummary(date: firstDay, timeZoneIdentifier: tokyo.identifier)])
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: secondDay, timeZoneIdentifier: tokyo.identifier))
        await mockCalculationService.enqueueUpcomingNights([makeNightSummary(date: secondDay, timeZoneIdentifier: tokyo.identifier)])

        let appController = AppController(
            locationController: locationController,
            calculationService: mockCalculationService
        )

        appController.onStart(referenceDate: firstActiveDate, refreshExternalData: false)

        await waitUntil(timeout: 1.0) {
            appController.nightSummary?.date == firstDay && appController.isUpcomingLoading == false
        }

        appController.handleSceneDidBecomeActive(referenceDate: secondActiveDate, refreshExternalData: false)

        await waitUntil(timeout: 1.0) {
            appController.selectedDate == secondDay
                && appController.nightSummary?.date == secondDay
                && appController.upcomingNights.first?.date == secondDay
        }

        XCTAssertEqual(appController.selectedDate, secondDay)
        XCTAssertEqual(appController.nightSummary?.date, secondDay)
        XCTAssertEqual(appController.upcomingNights.first?.date, secondDay)
    }

    func test_handleSceneDidBecomeActive_preservesCustomSelectedDateAcrossDayBoundary() async {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let storage = InMemoryLocationStorage()
        storage.timeZoneIdentifier = tokyo.identifier
        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                details: ResolvedLocationDetails(name: "東京", timeZoneIdentifier: tokyo.identifier)
            )
        )
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: tokyo)
        let firstActiveDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 21))!
        let secondActiveDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 7))!
        let trackedDay = ObservationTimeZone.startOfDay(for: firstActiveDate, timeZone: tokyo)
        let customDay = ObservationTimeZone.date(byAdding: .day, value: 3, to: trackedDay, timeZone: tokyo) ?? trackedDay

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: trackedDay, timeZoneIdentifier: tokyo.identifier))
        await mockCalculationService.enqueueUpcomingNights([makeNightSummary(date: trackedDay, timeZoneIdentifier: tokyo.identifier)])
        await mockCalculationService.enqueueUpcomingNights([makeNightSummary(date: trackedDay, timeZoneIdentifier: tokyo.identifier)])

        let appController = AppController(
            locationController: locationController,
            calculationService: mockCalculationService
        )

        appController.onStart(referenceDate: firstActiveDate, refreshExternalData: false)

        await waitUntil(timeout: 1.0) {
            appController.nightSummary?.date == trackedDay && appController.isUpcomingLoading == false
        }

        appController.selectedDate = customDay
        appController.handleSceneDidBecomeActive(referenceDate: secondActiveDate, refreshExternalData: false)

        await waitUntil(timeout: 1.0) {
            appController.isUpcomingLoading == false
        }

        XCTAssertEqual(appController.selectedDate, customDay)
    }

    func test_locationRefreshDisposition_appliesAll_whenSelectionStillMatches() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let request = AppController.LocationRefreshRequest(
            selectedDate: appController.selectedDate,
            coordinate: appController.locationController.selectedLocation,
            timeZoneIdentifier: appController.locationController.selectedTimeZone.identifier
        )

        XCTAssertEqual(appController.locationRefreshDisposition(for: request), .applyAll)
    }

    func test_locationRefreshDisposition_appliesLocationDataOnly_whenSelectedDateChanged() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let request = AppController.LocationRefreshRequest(
            selectedDate: appController.selectedDate,
            coordinate: appController.locationController.selectedLocation,
            timeZoneIdentifier: appController.locationController.selectedTimeZone.identifier
        )

        appController.selectedDate = appController.selectedDate.addingTimeInterval(86_400)

        XCTAssertEqual(appController.locationRefreshDisposition(for: request), .applyLocationDataOnly)
    }

    func test_locationRefreshDisposition_appliesAll_whenOnlyTimeComponentDiffers() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let request = AppController.LocationRefreshRequest(
            selectedDate: appController.selectedDate,
            coordinate: appController.locationController.selectedLocation,
            timeZoneIdentifier: appController.locationController.selectedTimeZone.identifier
        )

        appController.selectedDate = appController.selectedDate.addingTimeInterval(3_600)

        XCTAssertEqual(appController.locationRefreshDisposition(for: request), .applyAll)
    }

    func test_locationRefreshDisposition_discards_whenLocationChanged() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let request = AppController.LocationRefreshRequest(
            selectedDate: appController.selectedDate,
            coordinate: appController.locationController.selectedLocation,
            timeZoneIdentifier: appController.locationController.selectedTimeZone.identifier
        )

        appController.locationController.selectedLocation = CLLocationCoordinate2D(
            latitude: request.coordinate.latitude + 1,
            longitude: request.coordinate.longitude + 1
        )

        XCTAssertEqual(appController.locationRefreshDisposition(for: request), .discard)
    }

    func test_prepareForLocationChange_clearsDisplayedStateBeforeRefreshCompletes() {
        let baseDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let night = makeNightSummary(date: baseDate)
        let nextNight = makeNightSummary(date: nextDate)
        let weatherSummary = makeWeatherSummary(date: baseDate)

        let appController = AppController(calculationService: MockNightCalculationService())
        appController.nightSummary = night
        appController.upcomingNights = [night, nextNight]
        appController.starGazingIndex = StarGazingIndex.compute(
            nightSummary: night,
            weather: weatherSummary,
            bortleClass: 4
        )
        appController.upcomingIndexes = [
            Calendar.current.startOfDay(for: baseDate): StarGazingIndex.compute(
                nightSummary: night,
                weather: weatherSummary,
                bortleClass: 4
            )
        ]
        appController.weatherService.weatherByDate = [
            appController.weatherService.dateKey(baseDate): weatherSummary
        ]
        appController.lightPollutionService.bortleClass = 4
        appController.isCalculating = false

        appController.prepareForLocationChange()

        XCTAssertNil(appController.nightSummary)
        XCTAssertTrue(appController.upcomingNights.isEmpty)
        XCTAssertNil(appController.starGazingIndex)
        XCTAssertTrue(appController.upcomingIndexes.isEmpty)
        XCTAssertTrue(appController.weatherService.weatherByDate.isEmpty)
        XCTAssertNil(appController.lightPollutionService.bortleClass)
        XCTAssertTrue(appController.isCalculating)
        XCTAssertTrue(appController.isUpcomingLoading)
    }

    func test_prepareForLocationChange_cancelsInFlightCalculations() async {
        let baseDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueNightSummary(
            makeNightSummary(date: baseDate),
            delayMilliseconds: 250
        )
        await mockCalculationService.enqueueUpcomingNights(
            [makeNightSummary(date: baseDate), makeNightSummary(date: nextDate)],
            delayMilliseconds: 250
        )

        let appController = AppController(calculationService: mockCalculationService)
        appController.recalculate()
        appController.recalculateUpcoming()

        appController.prepareForLocationChange()

        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertNil(appController.nightSummary)
        XCTAssertTrue(appController.upcomingNights.isEmpty)
        XCTAssertTrue(appController.upcomingIndexes.isEmpty)
        XCTAssertTrue(appController.isCalculating)
        XCTAssertTrue(appController.isUpcomingLoading)
    }

    func test_applyLocationRefresh_recalculatesCurrentNightAfterSelectedDateChanged() async {
        let baseDate = Calendar.current.startOfDay(for: Date())
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate

        let mockCalculationService = MockNightCalculationService()
        await mockCalculationService.enqueueNightSummary(makeNightSummary(date: nextDate))
        let appController = AppController(calculationService: mockCalculationService)

        appController.selectedDate = nextDate
        appController.isCalculating = true

        let payload = AppController.LocationRefreshPayload(
            nightSummary: makeNightSummary(date: baseDate),
            upcomingNights: [makeNightSummary(date: baseDate)],
            weatherResult: WeatherService.FetchResult(
                weatherByDate: [:],
                errorMessage: nil,
                lastModifiedDate: nil,
                locationKey: "mock",
                timeZoneIdentifier: appController.locationController.selectedTimeZone.identifier
            ),
            lightPollutionResult: LightPollutionService.FetchResult(
                bortleClass: 4,
                fetchFailed: false,
                lastFetchedCoordinate: nil
            ),
            starGazingIndex: StarGazingIndex.compute(
                nightSummary: makeNightSummary(date: baseDate),
                weather: nil,
                bortleClass: 4
            ),
            upcomingIndexes: [:]
        )

        appController.applyLocationRefresh(payload, disposition: .applyLocationDataOnly)

        await waitUntil(timeout: 2.0) {
            appController.nightSummary?.date == nextDate && appController.isCalculating == false
        }

        XCTAssertEqual(appController.nightSummary?.date, nextDate)
    }

    func test_selectedDate_preservesCalendarDayWhenTimeZoneChanges() async {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let storage = InMemoryLocationStorage()
        storage.latitude = 35.6762
        storage.longitude = 139.6503
        storage.name = "東京"
        storage.timeZoneIdentifier = tokyo.identifier

        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                details: ResolvedLocationDetails(
                    name: "ロサンゼルス",
                    timeZoneIdentifier: losAngeles.identifier
                )
            )
        )
        let appController = AppController(
            locationController: locationController,
            calculationService: MockNightCalculationService()
        )

        let selectedDate = ObservationTimeZone.gregorianCalendar(timeZone: tokyo).date(
            from: DateComponents(year: 2026, month: 8, day: 12)
        )!
        appController.selectedDate = selectedDate

        locationController.selectCoordinate(
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        )

        await waitUntil(timeout: 2.0) {
            let components = ObservationTimeZone.gregorianCalendar(timeZone: losAngeles)
                .dateComponents([.year, .month, .day, .hour, .minute], from: appController.selectedDate)
            return locationController.selectedTimeZone.identifier == losAngeles.identifier
                && components.year == 2026
                && components.month == 8
                && components.day == 12
                && components.hour == 0
                && components.minute == 0
        }

        let components = ObservationTimeZone.gregorianCalendar(timeZone: losAngeles)
            .dateComponents([.year, .month, .day, .hour, .minute], from: appController.selectedDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func test_NightCalculationService_calculateUpcomingNights_stopsAfterCancellation() async {
        let recorder = CalculationInvocationRecorder()
        let service = NightCalculationService { date, location, _ in
            recorder.record(date)
            Thread.sleep(forTimeInterval: 0.05)
            return NightSummary(
                date: date,
                location: location,
                events: [],
                viewingWindows: [],
                moonPhaseAtMidnight: 0
            )
        }
        let location = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let baseDate = Calendar.current.startOfDay(for: Date())

        let task = Task {
            await service.calculateUpcomingNights(
                from: baseDate,
                location: location,
                timeZone: .current,
                days: 20
            )
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        task.cancel()
        let summaries = await task.value

        XCTAssertLessThan(summaries.count, 20)
        XCTAssertEqual(recorder.count, summaries.count)
    }
}

actor MockNightCalculationService: NightCalculating {
    private var nightSummaryResponses: [(summary: NightSummary, delayNanoseconds: UInt64)] = []
    private var upcomingResponses: [(summaries: [NightSummary], delayNanoseconds: UInt64)] = []
    private var nightSummaryCallCount = 0
    private var upcomingCallCount = 0

    func enqueueNightSummary(_ summary: NightSummary, delayMilliseconds: UInt64 = 0) {
        nightSummaryResponses.append((summary, delayMilliseconds * 1_000_000))
    }

    func enqueueUpcomingNights(_ summaries: [NightSummary], delayMilliseconds: UInt64 = 0) {
        upcomingResponses.append((summaries, delayMilliseconds * 1_000_000))
    }

    func calculateNightSummary(
        date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) async -> NightSummary {
        nightSummaryCallCount += 1
        guard !nightSummaryResponses.isEmpty else {
            return .placeholder
        }
        let response = nightSummaryResponses.removeFirst()
        if response.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: response.delayNanoseconds)
        }
        return response.summary
    }

    func calculateUpcomingNights(
        from date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone,
        days: Int
    ) async -> [NightSummary] {
        upcomingCallCount += 1
        guard !upcomingResponses.isEmpty else {
            return []
        }
        let response = upcomingResponses.removeFirst()
        if response.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: response.delayNanoseconds)
        }
        return response.summaries
    }

    func getNightSummaryCallCount() -> Int {
        nightSummaryCallCount
    }

    func getUpcomingCallCount() -> Int {
        upcomingCallCount
    }
}
