import XCTest
@testable import NightScope

final class WeatherModelsTests: XCTestCase {

    // MARK: - Helpers

    private func makeHourlyWeather(temperature: Double, dewpoint: Double) -> HourlyWeather {
        HourlyWeather(
            date: Date(),
            temperatureCelsius: temperature,
            cloudCoverPercent: 0,
            precipitationMM: 0,
            windSpeedKmh: 0,
            humidityPercent: 50,
            dewpointCelsius: dewpoint,
            weatherCode: 0,
            visibilityMeters: nil,
            windGustsKmh: nil,
            windSpeedKmh500hpa: nil
        )
    }

    // spread = temperature - dewpoint

    // MARK: - dewRiskLevel

    /// nighttimeHours が空のとき nil を返す
    func test_dewRiskLevel_emptyHours_returnsNil() {
        let summary = DayWeatherSummary(date: Date(), nighttimeHours: [])
        XCTAssertNil(summary.dewRiskLevel)
    }

    /// 平均 spread が 1.5°（< 2.0）のとき .high を返す
    func test_dewRiskLevel_spread1_5_returnsHigh() {
        // spread = 20.0 - 18.5 = 1.5
        let hours = [makeHourlyWeather(temperature: 20.0, dewpoint: 18.5)]
        let summary = DayWeatherSummary(date: Date(), nighttimeHours: hours)
        XCTAssertEqual(summary.dewRiskLevel, .high)
    }

    /// 平均 spread が 3.0°（2.0 ≤ spread < 5.0）のとき .medium を返す
    func test_dewRiskLevel_spread3_0_returnsMedium() {
        // spread = 23.0 - 20.0 = 3.0
        let hours = [makeHourlyWeather(temperature: 23.0, dewpoint: 20.0)]
        let summary = DayWeatherSummary(date: Date(), nighttimeHours: hours)
        XCTAssertEqual(summary.dewRiskLevel, .medium)
    }

    /// 平均 spread が 6.0°（≥ 5.0）のとき .low を返す
    func test_dewRiskLevel_spread6_0_returnsLow() {
        // spread = 26.0 - 20.0 = 6.0
        let hours = [makeHourlyWeather(temperature: 26.0, dewpoint: 20.0)]
        let summary = DayWeatherSummary(date: Date(), nighttimeHours: hours)
        XCTAssertEqual(summary.dewRiskLevel, .low)
    }

    /// 複数時間の平均 spread が閾値境界付近で正しく分類される
    func test_dewRiskLevel_averageSpread_usedCorrectly() {
        // h1: spread = 1.0, h2: spread = 3.0 → avg = 2.0 → .medium (spread < 5.0, ≥ 2.0)
        let h1 = makeHourlyWeather(temperature: 11.0, dewpoint: 10.0)  // spread = 1.0
        let h2 = makeHourlyWeather(temperature: 13.0, dewpoint: 10.0)  // spread = 3.0
        let summary = DayWeatherSummary(date: Date(), nighttimeHours: [h1, h2])
        XCTAssertEqual(summary.avgDewpointSpread, 2.0, accuracy: 0.001)
        XCTAssertEqual(summary.dewRiskLevel, .medium)
    }
}
