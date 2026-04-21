import XCTest
import CoreLocation
@testable import NightScope

final class AstroModelsTests: XCTestCase {
    private func makeOffsetDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        timeZoneIdentifier: String = "Asia/Tokyo"
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: timeZoneIdentifier)
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
            windSpeedKmh500hpa: nil
        )
    }

    private func makeSummary(
        events: [AstroEvent],
        timeZoneIdentifier: String = "Asia/Tokyo"
    ) -> NightSummary {
        NightSummary(
            date: events.first?.date ?? Date(),
            location: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0),
            events: events,
            viewingWindows: [],
            moonPhaseAtMidnight: 0.1,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    func test_weatherAwareObservableWindow_mergesAcrossMidnight() {
        let evening = makeDate(2026, 4, 2, 23, 45)
        let morning = makeDate(2026, 4, 3, 0, 0)

        let summary = makeSummary(events: [
            makeEvent(date: evening),
            makeEvent(date: morning)
        ])

        let hours = [
            makeWeatherHour(date: makeDate(2026, 4, 2, 23, 0)),
            makeWeatherHour(date: makeDate(2026, 4, 3, 0, 0))
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

        XCTAssertEqual(summary.weatherAwareRangeText(nighttimeHours: hours), L10n.tr("月明かり"))
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

    func test_weatherAwareObservableWindow_distinguishesRepeatedDstHours() {
        let losAngeles = "America/Los_Angeles"
        let firstHour = makeOffsetDate("2024-11-03T23:00:00-08:00")
        let firstEvent = makeOffsetDate("2024-11-03T23:15:00-08:00")
        let secondHour = makeOffsetDate("2024-11-04T01:00:00-08:00")
        let secondEvent = makeOffsetDate("2024-11-04T01:15:00-08:00")
        let summary = makeSummary(
            events: [
                makeEvent(date: firstEvent),
                makeEvent(date: secondEvent)
            ],
            timeZoneIdentifier: losAngeles
        )

        let hours = [
            makeWeatherHour(date: firstHour, cloud: 95, precipitation: 1.0, weatherCode: 61),
            makeWeatherHour(date: secondHour, cloud: 0, precipitation: 0, weatherCode: 0)
        ]

        let window = summary.weatherAwareObservableWindow(nighttimeHours: hours)
        XCTAssertEqual(window?.start, secondEvent)
        XCTAssertEqual(window?.end, secondEvent.addingTimeInterval(15 * 60))
    }

    func test_weatherAwareObservableWindow_mergesAcrossMidnightOnDstEndNight() {
        let losAngeles = "America/Los_Angeles"
        let morning = makeOffsetDate("2024-11-04T00:00:00-08:00")
        let evening = makeOffsetDate("2024-11-03T23:45:00-08:00")
        let summary = makeSummary(
            events: [
                makeEvent(date: evening),
                makeEvent(date: morning)
            ],
            timeZoneIdentifier: losAngeles
        )

        let hours = [
            makeWeatherHour(date: evening),
            makeWeatherHour(date: morning)
        ]

        let window = summary.weatherAwareObservableWindow(nighttimeHours: hours)
        XCTAssertEqual(window?.start, evening)
        XCTAssertEqual(window?.end, morning.addingTimeInterval(15 * 60))
    }

    func test_weatherAwareRangeText_returnsNilWhenNightWeatherCoverageIsIncomplete() {
        let evening = makeDate(2026, 4, 2, 23, 45)
        let morning = makeDate(2026, 4, 3, 0, 0)
        let summary = makeSummary(events: [
            makeEvent(date: evening),
            makeEvent(date: morning)
        ])

        let hours = [
            makeWeatherHour(date: makeDate(2026, 4, 2, 23, 0))
        ]

        XCTAssertNil(summary.weatherAwareRangeText(nighttimeHours: hours))
    }
}
