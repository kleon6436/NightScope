import XCTest
import CoreLocation
@testable import NightScope

final class AstroModelsTests: XCTestCase {

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func makeEvent(
        date: Date,
        sunAltitude: Double = -20,
        moonAltitude: Double = -5,
        moonPhase: Double = 0.1
    ) -> AstroEvent {
        AstroEvent(
            date: date,
            galacticCenterAltitude: 25,
            galacticCenterAzimuth: 180,
            sunAltitude: sunAltitude,
            moonAltitude: moonAltitude,
            moonPhase: moonPhase
        )
    }

    private func makeWeatherHour(
        date: Date,
        cloud: Double = 10,
        precipitation: Double = 0,
        weatherCode: Int = 0
    ) -> HourlyWeather {
        HourlyWeather(
            date: date,
            temperatureCelsius: 10,
            cloudCoverPercent: cloud,
            precipitationMM: precipitation,
            windSpeedKmh: 5,
            humidityPercent: 50,
            dewpointCelsius: 3,
            weatherCode: weatherCode,
            visibilityMeters: 20000,
            windGustsKmh: 10,
            cloudCoverLowPercent: nil,
            cloudCoverMidPercent: nil,
            cloudCoverHighPercent: nil,
            windSpeedKmh500hpa: nil
        )
    }

    private func makeSummary(events: [AstroEvent]) -> NightSummary {
        NightSummary(
            date: events.first?.date ?? Date(),
            location: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0),
            events: events,
            viewingWindows: [],
            moonPhaseAtMidnight: 0.1
        )
    }

    func test_weatherAwareObservableWindow_mergesAcrossMidnight() {
        let evening = makeDate(2026, 4, 2, 23, 45)
        // 実装は同一日の 0時台イベントを +24h 補正して夜跨ぎ連続性を判定する
        let morning = makeDate(2026, 4, 2, 0, 0)

        let summary = makeSummary(events: [
            makeEvent(date: evening),
            makeEvent(date: morning)
        ])

        let hours = [
            makeWeatherHour(date: makeDate(2026, 4, 2, 23, 0)),
            makeWeatherHour(date: makeDate(2026, 4, 2, 0, 0))
        ]

        let window = summary.weatherAwareObservableWindow(nighttimeHours: hours)
        XCTAssertEqual(window?.start, evening)
        XCTAssertEqual(window?.end, morning.addingTimeInterval(15 * 60))
    }

    func test_weatherAwareObservableWindow_returnsNilWhenMoonTooBright() {
        let date = makeDate(2026, 4, 2, 22, 0)
        let summary = makeSummary(events: [
            makeEvent(date: date, moonAltitude: 20, moonPhase: 0.5)
        ])

        let hours = [
            makeWeatherHour(date: date, cloud: 0, precipitation: 0, weatherCode: 0)
        ]

        XCTAssertNil(summary.weatherAwareObservableWindow(nighttimeHours: hours))
    }

    func test_weatherAwareRangeText_returnsMoonLightWhenWeatherClear() {
        let date = makeDate(2026, 4, 2, 22, 0)
        let summary = makeSummary(events: [
            makeEvent(date: date, moonAltitude: 30, moonPhase: 0.5)
        ])

        let hours = [
            makeWeatherHour(date: date, cloud: 0, precipitation: 0, weatherCode: 0)
        ]

        XCTAssertEqual(summary.weatherAwareRangeText(nighttimeHours: hours), "月明かり")
    }

    func test_weatherAwareRangeText_returnsEmptyWhenWeatherBad() {
        let date = makeDate(2026, 4, 2, 22, 0)
        let summary = makeSummary(events: [
            makeEvent(date: date, moonAltitude: -10, moonPhase: 0.1)
        ])

        let hours = [
            makeWeatherHour(date: date, cloud: 90, precipitation: 1.0, weatherCode: 61)
        ]

        XCTAssertEqual(summary.weatherAwareRangeText(nighttimeHours: hours), "")
    }
}
