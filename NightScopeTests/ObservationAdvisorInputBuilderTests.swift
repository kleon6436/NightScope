import XCTest
@testable import NightScope

final class ObservationAdvisorInputBuilderTests: XCTestCase {
    func test_build_formatsStringOnlyFieldsWithoutRawAstronomyDoubles() {
        let summary = makeNightSummary()
        let index = StarGazingIndex.compute(
            nightSummary: summary,
            weather: makeDayWeatherSummary(),
            bortleClass: 4
        )

        let input = ObservationAdvisorInputBuilder.build(
            nightSummary: summary,
            index: index,
            weather: makeDayWeatherSummary(),
            bortleClass: 4,
            locationName: "長野県 乗鞍高原",
            timeZone: .init(identifier: "Asia/Tokyo") ?? .current,
            locale: Locale(identifier: "ja_JP")
        )

        let joined = [
            input.dateString,
            input.locationName,
            input.tierLabel,
            input.viewingWindowSummary,
            input.moonSummary,
            input.weatherSummary,
            input.lightPollutionSummary
        ]
        .joined(separator: "\n")

        XCTAssertNil(joined.range(of: #"\d+\.\d+"#, options: .regularExpression))
    }

    func test_moonSummary_coversRepresentativePhases() {
        let phases: [(Double, String)] = [
            (0.0, "新月"),
            (0.10, "繊月"),
            (0.26, "上弦の月"),
            (0.40, "十日月"),
            (0.50, "満月"),
            (0.74, "下弦の月"),
            (0.90, "有明月")
        ]

        for (phase, expected) in phases {
            let summary = makeNightSummary(moonPhase: phase)
            let index = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: 4)
            let input = ObservationAdvisorInputBuilder.build(
                nightSummary: summary,
                index: index,
                weather: nil,
                bortleClass: 4,
                locationName: "東京",
                timeZone: .current,
                locale: Locale(identifier: "ja_JP")
            )
            XCTAssertTrue(input.moonSummary.contains(expected))
        }
    }

    func test_build_handlesMissingWeatherGracefully() {
        let summary = makeNightSummary()
        let index = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)

        let input = ObservationAdvisorInputBuilder.build(
            nightSummary: summary,
            index: index,
            weather: nil,
            bortleClass: nil,
            locationName: "",
            timeZone: .current,
            locale: Locale(identifier: "ja_JP")
        )

        XCTAssertEqual(input.weatherSummary, "天気データなし")
        XCTAssertEqual(input.locationName, "観測地未設定")
        XCTAssertEqual(input.language, "ja")
    }

    func test_build_usesEnglishSummariesForEnglishLocale() {
        let summary = makeNightSummary(date: Date(timeIntervalSince1970: 1_778_630_400), moonPhase: 0.12)
        let weather = makeDayWeatherSummary(cloudCover: 10, weatherCode: 0, windSpeed: 5)
        let index = StarGazingIndex.compute(
            nightSummary: summary,
            weather: weather,
            bortleClass: 4
        )

        let input = ObservationAdvisorInputBuilder.build(
            nightSummary: summary,
            index: index,
            weather: weather,
            bortleClass: 4,
            locationName: "",
            timeZone: .init(identifier: "America/Los_Angeles") ?? .current,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(input.language, "en")
        XCTAssertEqual(input.locationName, "Observation location not set")
        XCTAssertEqual(input.tierLabel, "Fair")
        XCTAssertTrue(input.viewingWindowSummary.contains("best around"))
        XCTAssertTrue(input.moonSummary.contains("Waxing Crescent"))
        XCTAssertTrue(input.weatherSummary.contains("Clear"))
        XCTAssertTrue(input.lightPollutionSummary.contains("Suburban sky"))
        XCTAssertFalse(input.dateString.contains("年"))
        XCTAssertFalse(input.viewingWindowSummary.contains("見頃"))
    }

    func test_supportedAdvisorLanguage_nonJapaneseLocales_returnEnglish() {
        XCTAssertEqual(ObservationAdvisorInputBuilder.supportedAdvisorLanguage(for: Locale(identifier: "zh_CN")), "en")
        XCTAssertEqual(ObservationAdvisorInputBuilder.supportedAdvisorLanguage(for: Locale(identifier: "fr_FR")), "en")
        XCTAssertEqual(ObservationAdvisorInputBuilder.supportedAdvisorLanguage(for: Locale(identifier: "ja_JP")), "ja")
    }

    func test_tierLabel_allTiersInEnglish() {
        let expectations: [(StarGazingIndex.Tier, String)] = [
            (.excellent, "Excellent"),
            (.good, "Good"),
            (.fair, "Fair"),
            (.poor, "Poor"),
            (.bad, "Very Poor")
        ]

        for (tier, expectedLabel) in expectations {
            let input = makeInput(tier: tier, locale: Locale(identifier: "en_US"))
            XCTAssertEqual(input.tierLabel, expectedLabel)
        }
    }

    func test_isUnfavorable_onlyForPoorAndBad() {
        let expectations: [(StarGazingIndex.Tier, Bool)] = [
            (.excellent, false),
            (.good, false),
            (.fair, false),
            (.poor, true),
            (.bad, true)
        ]

        for (tier, expectedValue) in expectations {
            let input = makeInput(tier: tier, locale: Locale(identifier: "en_US"))
            XCTAssertEqual(input.isUnfavorable, expectedValue)
        }
    }

    private func makeInput(
        tier: StarGazingIndex.Tier,
        locale: Locale
    ) -> ObservationAdvisorInput {
        let summary = makeNightSummary()
        let score: Int = switch tier {
        case .excellent: 90
        case .good: 75
        case .fair: 50
        case .poor: 35
        case .bad: 34
        }
        let index = StarGazingIndex(
            score: score,
            milkyWayScore: 0,
            constellationScore: 0,
            weatherScore: 0,
            lightPollutionScore: 0,
            hasWeatherData: true,
            hasLightPollutionData: true
        )

        return ObservationAdvisorInputBuilder.build(
            nightSummary: summary,
            index: index,
            weather: nil,
            bortleClass: nil,
            locationName: "Test",
            timeZone: .current,
            locale: locale
        )
    }
}
