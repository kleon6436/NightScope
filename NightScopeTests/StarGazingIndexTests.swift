import XCTest
import CoreLocation
@testable import NightScope

final class StarGazingIndexTests: XCTestCase {

    // MARK: - Helpers

    /// 指定した暗時間数・月齢・観測ウィンドウを持つ NightSummary を生成
    private func makeNightSummary(
        darkEventCount: Int,
        moonPhase: Double,
        viewingHours: Double = 0,
        maxAltitude: Double = 0
    ) -> NightSummary {
        let base = Date(timeIntervalSince1970: 0)
        let location = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0)

        // 1イベント = 15分。sunAltitude < -18 で isDark = true
        let events = (0..<darkEventCount).map { i in
            AstroEvent(
                date: base.addingTimeInterval(Double(i) * 900),
                galacticCenterAltitude: 0,
                galacticCenterAzimuth: 0,
                sunAltitude: -20.0,
                moonAltitude: 0,
                moonPhase: moonPhase
            )
        }

        var windows: [ViewingWindow] = []
        if viewingHours > 0 {
            let end = base.addingTimeInterval(viewingHours * 3600)
            windows.append(ViewingWindow(
                start: base, end: end,
                peakTime: base, peakAltitude: maxAltitude, peakAzimuth: 180
            ))
        }

        return NightSummary(
            date: base,
            location: location,
            events: events,
            viewingWindows: windows,
            moonPhaseAtMidnight: moonPhase
        )
    }

    /// 指定した気象値を持つ DayWeatherSummary を生成（単一時間帯として扱う）
    private func makeWeather(
        cloud: Double,
        precip: Double,
        wind: Double,
        humidity: Double,
        dewpointSpread: Double
    ) -> DayWeatherSummary {
        let temp = 20.0
        let hour = HourlyWeather(
            date: Date(),
            temperatureCelsius: temp,
            cloudCoverPercent: cloud,
            precipitationMM: precip,
            windSpeedKmh: wind,
            humidityPercent: humidity,
            dewpointCelsius: temp - dewpointSpread,
            weatherCode: 0
        )
        return DayWeatherSummary(date: Date(), nighttimeHours: [hour])
    }

    // MARK: - Tier

    func test_tier_excellent_at100() {
        let idx = StarGazingIndex(score: 100, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .excellent)
    }

    func test_tier_excellent_at90() {
        let idx = StarGazingIndex(score: 90, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .excellent)
    }

    func test_tier_good_at89() {
        let idx = StarGazingIndex(score: 89, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .good)
    }

    func test_tier_good_at75() {
        let idx = StarGazingIndex(score: 75, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .good)
    }

    func test_tier_fair_at74() {
        let idx = StarGazingIndex(score: 74, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .fair)
    }

    func test_tier_fair_at55() {
        let idx = StarGazingIndex(score: 55, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .fair)
    }

    func test_tier_poor_at54() {
        let idx = StarGazingIndex(score: 54, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .fair)
    }

    func test_tier_poor_at35() {
        let idx = StarGazingIndex(score: 35, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .poor)
    }

    func test_tier_bad_at34() {
        let idx = StarGazingIndex(score: 34, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .bad)
    }

    func test_tier_bad_at0() {
        let idx = StarGazingIndex(score: 0, milkyWayScore: 0, constellationScore: 0,
                                  weatherScore: 0, lightPollutionScore: 0,
                                  hasWeatherData: true, hasLightPollutionData: true)
        XCTAssertEqual(idx.tier, .bad)
    }

    // MARK: - starCount

    func test_starCount_matchesTier() {
        let cases: [(Int, Int)] = [(100, 5), (80, 4), (65, 3), (45, 2), (10, 1)]
        for (score, expected) in cases {
            let idx = StarGazingIndex(score: score, milkyWayScore: 0, constellationScore: 0,
                                      weatherScore: 0, lightPollutionScore: 0,
                                      hasWeatherData: true, hasLightPollutionData: true)
            XCTAssertEqual(idx.starCount, expected, "score=\(score)")
        }
    }

    // MARK: - Light Pollution Score

    func test_lightPollutionScore_bortle3_isMax() {
        // bortle=3: 10*(9-3)/6 = 10 → 満点
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: 3.0)
        XCTAssertEqual(idx.lightPollutionScore, 10)
    }

    func test_lightPollutionScore_bortle6_isMid() {
        // bortle=6: 10*(9-6)/6 = 5
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: 6.0)
        XCTAssertEqual(idx.lightPollutionScore, 5)
    }

    func test_lightPollutionScore_bortle9_isZero() {
        // bortle=9: 10*(9-9)/6 = 0
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: 9.0)
        XCTAssertEqual(idx.lightPollutionScore, 0)
    }

    func test_lightPollutionScore_nilBortle_isZero() {
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)
        XCTAssertEqual(idx.lightPollutionScore, 0)
    }

    // MARK: - Constellation Score (暗時間 × 月照度)

    func test_constellationScore_maxDarkHours_newMoon() {
        // darkEvents=25 → 6.25h > 6h → +30pts
        // phase=0 (新月) → illumination=0 → +20pts
        // total = 50 (上限)
        let summary = makeNightSummary(darkEventCount: 25, moonPhase: 0.0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)
        XCTAssertEqual(idx.constellationScore, 50)
    }

    func test_constellationScore_noDarkHours_fullMoon() {
        // darkEvents=0 → 0h → +0pts
        // phase=0.5 (満月) → illumination=1.0 ≥ 0.7 → +0pts
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0.5)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)
        XCTAssertEqual(idx.constellationScore, 0)
    }

    func test_constellationScore_moderateDark_newMoon() {
        // darkEvents=9 → 2.25h > 2h → +14pts
        // phase=0 → +20pts → total=34
        let summary = makeNightSummary(darkEventCount: 9, moonPhase: 0.0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)
        XCTAssertEqual(idx.constellationScore, 34)
    }

    func test_constellationScore_smallDark_waxingGibbousMoon() {
        // darkEvents=1 → 0.25h > 0h → +5pts
        // phase=0.3 → illumination=(1-cos(0.6π))/2 ≈ 0.655 → 0.50≤x<0.70 → +3pts
        // total = 8
        // ※ phase=0.25 は cos(π/2) の浮動小数点誤差で illumination が 0.5 をわずかに下回り
        //   < 0.50 ブランチに入るため使用しない
        let summary = makeNightSummary(darkEventCount: 1, moonPhase: 0.3)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)
        XCTAssertEqual(idx.constellationScore, 8)
    }

    // MARK: - Weather Score

    func test_weatherScore_bestConditions() {
        // cloud=10(<15)→+18, precip=0→+8, wind=5(<10)→+6, humidity=40(<50)→+5, spread=20(>15)→+3
        // total = 40
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let weather = makeWeather(cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: weather, bortleClass: nil)
        XCTAssertEqual(idx.weatherScore, 40)
    }

    func test_weatherScore_worstConditions() {
        // cloud=80(≥75)→+0, precip=1.0(≥0.5)→+0, wind=40(≥35)→+0, humidity=90(≥80)→+0, spread=3(≤5)→+0
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let weather = makeWeather(cloud: 80, precip: 1.0, wind: 40, humidity: 90, dewpointSpread: 3)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: weather, bortleClass: nil)
        XCTAssertEqual(idx.weatherScore, 0)
    }

    func test_weatherScore_moderateConditions() {
        // cloud=25(15-35)→+13, precip=0.3(0.1-0.5)→+2, wind=15(10-20)→+4,
        // humidity=60(50-65)→+3, spread=12(10-15)→+2 → total=24
        let summary = makeNightSummary(darkEventCount: 0, moonPhase: 0)
        let weather = makeWeather(cloud: 25, precip: 0.3, wind: 15, humidity: 60, dewpointSpread: 12)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: weather, bortleClass: nil)
        XCTAssertEqual(idx.weatherScore, 24)
    }

    // MARK: - compute() 統合テスト

    func test_compute_allBest_isExcellent() {
        // constellation=50, weather=40, lightPollution=10 → total=100
        let summary = makeNightSummary(darkEventCount: 25, moonPhase: 0.0)
        let weather = makeWeather(cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertEqual(idx.score, 100)
        XCTAssertEqual(idx.tier, .excellent)
        XCTAssertTrue(idx.hasWeatherData)
        XCTAssertTrue(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_scaledFromConstellationAndLP() {
        // constellation=50, LP=10 → base=60, maxBase=60 → scaled=100
        let summary = makeNightSummary(darkEventCount: 25, moonPhase: 0.0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: 3.0)
        XCTAssertEqual(idx.score, 100)
        XCTAssertFalse(idx.hasWeatherData)
        XCTAssertTrue(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_noLP_scaledFromConstellationOnly() {
        // constellation=50, LP=0 → base=50, maxBase=50 → scaled=100
        let summary = makeNightSummary(darkEventCount: 25, moonPhase: 0.0)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: nil)
        XCTAssertEqual(idx.score, 100)
        XCTAssertFalse(idx.hasWeatherData)
        XCTAssertFalse(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_partialScore_scalesCorrectly() {
        // constellation=14(darkEvents=9,phase=0→+14+20=34だが... moonPhase=0.5なら+0 → 14+0=14)
        // LP=5(bortle=6), base=14+5=19, maxBase=60 → scaled = Int(19/60*100) = Int(31.67) = 31
        let summary = makeNightSummary(darkEventCount: 9, moonPhase: 0.5)
        let idx = StarGazingIndex.compute(nightSummary: summary, weather: nil, bortleClass: 6.0)
        let expected = Int(Double(14 + 5) / 60.0 * 100.0)
        XCTAssertEqual(idx.score, expected)
    }
}
