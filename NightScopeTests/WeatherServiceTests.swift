import XCTest
import CoreLocation
import WeatherKit
@testable import NightScope

@MainActor
final class WeatherServiceTests: XCTestCase {

    private let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    private let tokyoLocation = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)

    // MARK: - WeatherKitService 初期状態

    func test_weatherKitService_initialState() {
        let service = WeatherKitService()
        XCTAssertTrue(service.weatherByDate.isEmpty)
        XCTAssertFalse(service.isLoading)
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - isForecastOutOfRange

    func test_weatherKitService_isForecastOutOfRange_returnsFalseWhenKeyExists() {
        let service = WeatherKitService()
        let tz = tokyoTimeZone
        let date = makeDateInTokyo(year: 2024, month: 6, day: 15)
        let key = service.dateKey(date, timeZone: tz)
        let summary = DayWeatherSummary(date: date, nighttimeHours: [])
        let weatherByDate = [key: summary]

        XCTAssertFalse(service.isForecastOutOfRange(for: date, in: weatherByDate, timeZone: tz))
    }

    func test_weatherKitService_isForecastOutOfRange_returnsTrueAfterLatestDay() {
        let service = WeatherKitService()
        let tz = tokyoTimeZone
        // 最新予報: 6/15
        let latestDate = makeDateInTokyo(year: 2024, month: 6, day: 15)
        let latestKey  = service.dateKey(latestDate, timeZone: tz)
        let weatherByDate = [latestKey: DayWeatherSummary(date: latestDate, nighttimeHours: [])]

        // 6/16 は範囲外
        let futureDate = makeDateInTokyo(year: 2024, month: 6, day: 16)
        XCTAssertTrue(service.isForecastOutOfRange(for: futureDate, in: weatherByDate, timeZone: tz))
    }

    func test_weatherKitService_isForecastOutOfRange_returnsFalseForEmptyWeather() {
        let service = WeatherKitService()
        let date = makeDateInTokyo(year: 2024, month: 6, day: 15)
        // 空の weatherByDate では latestForecastDate が取れず false
        XCTAssertFalse(service.isForecastOutOfRange(for: date, in: [:], timeZone: tokyoTimeZone))
    }

    // MARK: - locationKey キャッシュ分離

    func test_weatherKitService_locationKey_cacheIsolation() {
        let service = WeatherKitService()
        let tz = tokyoTimeZone

        let tokyoDate = makeDateInTokyo(year: 2024, month: 6, day: 15)
        let osakaDate = makeDateInTokyo(year: 2024, month: 6, day: 15)

        // 東京: 35.6762, 139.6503
        let tokyoKey = service.dateKey(tokyoDate, timeZone: tz)
        let tokyoSummary = DayWeatherSummary(date: tokyoDate, nighttimeHours: [])
        let tokyoResult = WeatherFetchResult(
            weatherByDate: [tokyoKey: tokyoSummary],
            errorMessage: nil,
            lastModifiedDate: nil,
            locationKey: "35.6762,139.6503|Asia/Tokyo",
            timeZoneIdentifier: tz.identifier
        )
        service.applyFetchResult(tokyoResult)
        XCTAssertFalse(service.weatherByDate.isEmpty, "東京の天気が反映されるべき")

        // 大阪: 34.6937, 135.5022
        let osakaKey = service.dateKey(osakaDate, timeZone: tz)
        let osakaSummary = DayWeatherSummary(date: osakaDate, nighttimeHours: [])
        let osakaResult = WeatherFetchResult(
            weatherByDate: [osakaKey: osakaSummary],
            errorMessage: nil,
            lastModifiedDate: nil,
            locationKey: "34.6937,135.5022|Asia/Tokyo",
            timeZoneIdentifier: tz.identifier
        )
        service.applyFetchResult(osakaResult)

        // 大阪に切り替わり、大阪のキャッシュが表示される
        XCTAssertFalse(service.weatherByDate.isEmpty, "大阪の天気が反映されるべき")
        XCTAssertEqual(service.weatherByDate[osakaKey]?.date, osakaDate)
    }

    // MARK: - dateKey フォーマット

    func test_weatherKitService_dateKey_format() {
        let service = WeatherKitService()
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        var comps = DateComponents()
        comps.year = 2024; comps.month = 6; comps.day = 15; comps.hour = 12
        comps.timeZone = tz
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(service.dateKey(date, timeZone: tz), "2024-06-15")
    }

    func test_weatherKitService_dateKey_singleDigitMonthAndDay_zeroPadded() {
        let service = WeatherKitService()
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 5; comps.hour = 12
        comps.timeZone = tz
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(service.dateKey(date, timeZone: tz), "2024-03-05")
    }

    // MARK: - WeatherConditionMapper

    func test_weatherConditionMapper_allCases_returnValidWMOCode() {
        let allConditions: [WeatherCondition] = [
            .clear, .mostlyClear, .partlyCloudy, .mostlyCloudy, .cloudy,
            .foggy, .drizzle, .freezingDrizzle, .rain, .heavyRain,
            .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms,
            .thunderstorms, .strongStorms, .hail, .blizzard, .wintryMix,
            .flurries, .snow, .sunFlurries, .blowingSnow, .heavySnow,
            .sleet, .freezingRain, .tropicalStorm, .hurricane,
            .breezy, .windy, .frigid, .hot, .haze, .smoky, .blowingDust
        ]
        for condition in allConditions {
            let code = WeatherConditionMapper.wmoCode(for: condition)
            XCTAssertTrue((0...99).contains(code),
                          "\(condition) → \(code) は有効な WMO コード範囲外です")
        }
    }

    func test_weatherConditionMapper_clearSky_returnsZero() {
        XCTAssertEqual(WeatherConditionMapper.wmoCode(for: .clear), 0)
    }

    func test_weatherConditionMapper_thunderstorm_returns95() {
        XCTAssertEqual(WeatherConditionMapper.wmoCode(for: .thunderstorms), 95)
    }

    func test_weatherConditionMapper_cloudy_returns3() {
        XCTAssertEqual(WeatherConditionMapper.wmoCode(for: .cloudy), 3)
    }

    func test_weatherConditionMapper_heavySnow_returns75() {
        XCTAssertEqual(WeatherConditionMapper.wmoCode(for: .heavySnow), 75)
    }

    func test_weatherConditionMapper_foggy_returns45() {
        XCTAssertEqual(WeatherConditionMapper.wmoCode(for: .foggy), 45)
    }

    // MARK: - Helpers

    private func makeDateInTokyo(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.timeZone = tokyoTimeZone
        comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
