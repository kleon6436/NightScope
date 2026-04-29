import XCTest
import Combine
import CoreLocation
@testable import NightScope

@MainActor
final class ComparisonControllerTests: XCTestCase {
    func test_refresh_buildsCellsForFavoriteLocations() async {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let favorite = FavoriteLocation(name: "Tokyo", latitude: 35.6762, longitude: 139.6503, timeZoneIdentifier: "Asia/Tokyo")
        let store = MockFavoriteLocationStore(favorites: [favorite])
        let weatherService = MockComparisonWeatherService()
        let lightPollutionService = MockComparisonLightPollutionService(bortleByCoordinate: ["35.6762,139.6503": 3.0])
        let calculationService = MockNightCalculationService()
        let night1 = makeNightSummary(date: baseDate, withWindow: true)
        let night2 = makeNightSummary(date: baseDate.addingTimeInterval(86_400), withWindow: true)
        await calculationService.enqueueUpcomingNights([night1, night2])
        weatherService.resultByLocationKey["35.6762,139.6503|Asia/Tokyo"] = weatherService.makeResult(
            dates: [night1.date, night2.date],
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )

        let controller = ComparisonController(
            favoriteStore: store,
            weatherService: weatherService,
            lightPollutionService: lightPollutionService,
            calculationService: calculationService
        )
        controller.dayCount = 2
        await controller.refresh(referenceDate: baseDate)

        XCTAssertEqual(controller.matrix.locations.count, 1)
        XCTAssertEqual(controller.matrix.dates.count, 2)
        XCTAssertEqual(controller.cell(for: favorite.id, date: controller.matrix.dates[0])?.loadState, .loaded)
        XCTAssertNotNil(controller.cell(for: favorite.id, date: controller.matrix.dates[0])?.index)
    }

    func test_bestCell_returnsHighestScoreForDate() async {
        let baseDate = Date(timeIntervalSince1970: 1_700_100_000)
        let favorites = [
            FavoriteLocation(name: "Dark", latitude: 35.0, longitude: 135.0, timeZoneIdentifier: "Asia/Tokyo"),
            FavoriteLocation(name: "Bright", latitude: 34.0, longitude: 135.0, timeZoneIdentifier: "Asia/Tokyo")
        ]
        let store = MockFavoriteLocationStore(favorites: favorites)
        let weatherService = MockComparisonWeatherService()
        let lightPollutionService = MockComparisonLightPollutionService(
            bortleByCoordinate: ["35.0000,135.0000": 3.0, "34.0000,135.0000": 7.0]
        )
        let calculationService = MockNightCalculationService()
        let darkNight = makeNightSummary(date: baseDate, withWindow: true)
        let brightNight = makeNightSummary(date: baseDate, withWindow: true)
        await calculationService.enqueueUpcomingNights([darkNight])
        await calculationService.enqueueUpcomingNights([brightNight])
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        weatherService.resultByLocationKey["35.0000,135.0000|Asia/Tokyo"] = weatherService.makeResult(dates: [darkNight.date], timeZone: tz)
        weatherService.resultByLocationKey["34.0000,135.0000|Asia/Tokyo"] = weatherService.makeResult(dates: [brightNight.date], timeZone: tz)

        let controller = ComparisonController(
            favoriteStore: store,
            weatherService: weatherService,
            lightPollutionService: lightPollutionService,
            calculationService: calculationService
        )
        controller.dayCount = 1
        await controller.refresh(referenceDate: baseDate)

        XCTAssertEqual(controller.bestCell(for: controller.matrix.dates[0])?.locationID, favorites[0].id)
    }

    func test_refresh_withNoFavorites_keepsMatrixEmpty() async {
        let controller = ComparisonController(
            favoriteStore: MockFavoriteLocationStore(favorites: []),
            weatherService: MockComparisonWeatherService(),
            lightPollutionService: MockComparisonLightPollutionService(bortleByCoordinate: [:]),
            calculationService: MockNightCalculationService()
        )

        await controller.refresh(referenceDate: Date())

        XCTAssertTrue(controller.matrix.locations.isEmpty)
        XCTAssertTrue(controller.matrix.cellsByID.isEmpty)
    }
}

private final class MockFavoriteLocationStore: FavoriteLocationStoring {
    private let favorites: [FavoriteLocation]

    init(favorites: [FavoriteLocation]) {
        self.favorites = favorites
    }

    func loadAll() -> [FavoriteLocation] { favorites }
    func save(_ favorites: [FavoriteLocation]) {}
}

@MainActor
private final class MockComparisonWeatherService: WeatherProviding {
    @Published var weatherByDate: [String: DayWeatherSummary] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    var resultByLocationKey: [String: WeatherFetchResult] = [:]

    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { $weatherByDate }
    var isLoadingPublisher: AnyPublisher<Bool, Never> { $isLoading.eraseToAnyPublisher() }
    var errorMessagePublisher: AnyPublisher<String?, Never> { $errorMessage.eraseToAnyPublisher() }

    func fetchWeather(latitude: Double, longitude: Double, timeZone: TimeZone) async {}
    func summary(for date: Date) -> DayWeatherSummary? { weatherByDate[dateKey(date, timeZone: .current)] }

    func fetchWeatherSnapshot(latitude: Double, longitude: Double, timeZone: TimeZone) async -> WeatherFetchResult {
        let locationKey = String(format: "%.4f,%.4f|%@", latitude, longitude, timeZone.identifier)
        return resultByLocationKey[locationKey] ?? WeatherFetchResult(
            weatherByDate: [:],
            errorMessage: nil,
            lastModifiedDate: nil,
            locationKey: locationKey,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    func applyFetchResult(_ result: WeatherFetchResult) {
        weatherByDate = result.weatherByDate
        errorMessage = result.errorMessage
    }

    func summary(for date: Date, from weatherByDate: [String : DayWeatherSummary], timeZone: TimeZone) -> DayWeatherSummary? {
        weatherByDate[dateKey(date, timeZone: timeZone)]
    }

    func isForecastOutOfRange(for date: Date, in weatherByDate: [String : DayWeatherSummary], timeZone: TimeZone) -> Bool { false }

    func dateKey(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func prepareForLocationChange(latitude: Double, longitude: Double, timeZone: TimeZone) {}

    func makeResult(dates: [Date], timeZone: TimeZone) -> WeatherFetchResult {
        let values = Dictionary(uniqueKeysWithValues: dates.map { date in
            let weather = DayWeatherSummary(date: date, nighttimeHours: [
                HourlyWeather(
                    date: date,
                    temperatureCelsius: 15,
                    cloudCoverPercent: 10,
                    precipitationMM: 0,
                    windSpeedKmh: 5,
                    humidityPercent: 40,
                    dewpointCelsius: 2,
                    weatherCode: 0,
                    visibilityMeters: 20_000,
                    windGustsKmh: 10,
                    windSpeedKmh500hpa: nil
                )
            ])
            return (dateKey(date, timeZone: timeZone), weather)
        })
        return WeatherFetchResult(
            weatherByDate: values,
            errorMessage: nil,
            lastModifiedDate: nil,
            locationKey: "",
            timeZoneIdentifier: timeZone.identifier
        )
    }
}

@MainActor
private final class MockComparisonLightPollutionService: LightPollutionProviding {
    @Published var bortleClass: Double?
    @Published var isLoading = false
    @Published var fetchFailed = false
    private let bortleByCoordinate: [String: Double]

    init(bortleByCoordinate: [String: Double]) {
        self.bortleByCoordinate = bortleByCoordinate
    }

    var bortleClassPublisher: Published<Double?>.Publisher { $bortleClass }
    var isLoadingPublisher: Published<Bool>.Publisher { $isLoading }
    var fetchFailedPublisher: Published<Bool>.Publisher { $fetchFailed }

    func fetch(latitude: Double, longitude: Double) async {}

    func fetchBortle(latitude: Double, longitude: Double) async throws -> Double {
        bortleByCoordinate[String(format: "%.4f,%.4f", latitude, longitude)] ?? 4.0
    }
}
