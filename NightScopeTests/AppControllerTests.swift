import XCTest
import CoreLocation
@testable import NightScope

@MainActor
final class AppControllerTests: XCTestCase {

    private func makeNightSummary(date: Date) -> NightSummary {
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
            moonPhaseAtMidnight: 0.12
        )
    }

    private func makeWeatherSummary(date: Date) -> DayWeatherSummary {
        let hourly = HourlyWeather(
            date: date,
            temperatureCelsius: 12,
            cloudCoverPercent: 15,
            precipitationMM: 0,
            windSpeedKmh: 5,
            humidityPercent: 40,
            dewpointCelsius: 2,
            weatherCode: 0,
            visibilityMeters: 20000,
            windGustsKmh: 10,
            cloudCoverLowPercent: 10,
            cloudCoverMidPercent: 10,
            cloudCoverHighPercent: 20,
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

        appController.upcomingNights = [night]
        appController.recomputeUpcomingIndexes()

        let dayKey = Calendar.current.startOfDay(for: night.date)
        XCTAssertEqual(appController.upcomingIndexes[dayKey]?.hasWeatherData, false)

        let weatherSummary = makeWeatherSummary(date: night.date)
        appController.weatherService.weatherByDate = [
            appController.weatherService.dateKey(night.date): weatherSummary
        ]

        await waitUntil {
            appController.upcomingIndexes[dayKey]?.hasWeatherData == true
        }

        XCTAssertEqual(appController.upcomingIndexes[dayKey]?.hasWeatherData, true)
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

    func calculateNightSummary(date: Date, location: CLLocationCoordinate2D) async -> NightSummary {
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

    func calculateUpcomingNights(from date: Date, location: CLLocationCoordinate2D, days: Int) async -> [NightSummary] {
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
