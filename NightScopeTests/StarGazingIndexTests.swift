import XCTest
import CoreLocation
@testable import NightScope

final class StarGazingIndexTests: XCTestCase {

    // MARK: - Helpers

    /// 指定した暗時間数・月齢・観測ウィンドウを持つ NightSummary を生成
    private func makeNightSummary(
        darkEventCount: Int = 0,
        moonPhase: Double = 0.0,
        viewingHours: Double = 0,
        maxAltitude: Double = 0,
        moonAltitude: Double = 30.0  // デフォルトは地平線上 (月スコアが月相に従って評価される)
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
                moonAltitude: moonAltitude,
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
        dewpointSpread: Double,
        visibility: Double? = nil,
        windGusts: Double? = nil,
        cloudLow: Double? = nil,
        cloudMid: Double? = nil,
        cloudHigh: Double? = nil,
        weatherCode: Int = 0,
        windSpeed500hpa: Double? = nil
    ) -> DayWeatherSummary {
        // makeNightSummary の events は Date(timeIntervalSince1970: 0) を基準にするため
        // HourlyWeather の日付も同じ基準にして時刻（hour-of-day）が一致するようにする
        let base = Date(timeIntervalSince1970: 0)
        let temp = 20.0
        let hour = HourlyWeather(
            date: base,
            temperatureCelsius: temp,
            cloudCoverPercent: cloud,
            precipitationMM: precip,
            windSpeedKmh: wind,
            humidityPercent: humidity,
            dewpointCelsius: temp - dewpointSpread,
            weatherCode: weatherCode,
            visibilityMeters: visibility,
            windGustsKmh: windGusts,
            cloudCoverLowPercent: cloudLow,
            cloudCoverMidPercent: cloudMid,
            cloudCoverHighPercent: cloudHigh,
            windSpeedKmh500hpa: windSpeed500hpa
        )
        return DayWeatherSummary(date: base, nighttimeHours: [hour])
    }

    private func makeHourlyWeather(
        base: Date,
        hourOffset: Int,
        cloud: Double,
        precip: Double,
        wind: Double,
        humidity: Double,
        dewpoint: Double,
        weatherCode: Int
    ) -> HourlyWeather {
        HourlyWeather(
            date: base.addingTimeInterval(Double(hourOffset) * 3600),
            temperatureCelsius: 15,
            cloudCoverPercent: cloud,
            precipitationMM: precip,
            windSpeedKmh: wind,
            humidityPercent: humidity,
            dewpointCelsius: dewpoint,
            weatherCode: weatherCode,
            visibilityMeters: nil,
            windGustsKmh: nil,
            cloudCoverLowPercent: nil,
            cloudCoverMidPercent: nil,
            cloudCoverHighPercent: nil,
            windSpeedKmh500hpa: nil
        )
    }

    private func makeIndex(score: Int) -> StarGazingIndex {
        StarGazingIndex(
            score: score,
            milkyWayScore: 0,
            constellationScore: 0,
            weatherScore: 0,
            lightPollutionScore: 0,
            hasWeatherData: true,
            hasLightPollutionData: true
        )
    }

    private func makeIdealDarkSummary() -> NightSummary {
        makeNightSummary(darkEventCount: 25)
    }

    private func computeIndex(
        nightSummary: NightSummary,
        weather: DayWeatherSummary? = nil,
        bortleClass: Double? = nil
    ) -> StarGazingIndex {
        StarGazingIndex.compute(
            nightSummary: nightSummary,
            weather: weather,
            bortleClass: bortleClass
        )
    }

    // MARK: - Tier

    func test_tier_excellent_at100() {
        let idx = makeIndex(score: 100)
        XCTAssertEqual(idx.tier, .excellent)
    }

    func test_tier_excellent_at90() {
        let idx = makeIndex(score: 90)
        XCTAssertEqual(idx.tier, .excellent)
    }

    func test_tier_good_at89() {
        let idx = makeIndex(score: 89)
        XCTAssertEqual(idx.tier, .good)
    }

    func test_tier_good_at75() {
        let idx = makeIndex(score: 75)
        XCTAssertEqual(idx.tier, .good)
    }

    func test_tier_fair_at74() {
        let idx = makeIndex(score: 74)
        XCTAssertEqual(idx.tier, .fair)
    }

    func test_tier_fair_at55() {
        let idx = makeIndex(score: 55)
        XCTAssertEqual(idx.tier, .fair)
    }

    func test_tier_fair_at54() {
        let idx = makeIndex(score: 54)
        XCTAssertEqual(idx.tier, .fair)
    }

    func test_tier_poor_at35() {
        let idx = makeIndex(score: 35)
        XCTAssertEqual(idx.tier, .poor)
    }

    func test_tier_bad_at34() {
        let idx = makeIndex(score: 34)
        XCTAssertEqual(idx.tier, .bad)
    }

    func test_tier_bad_at0() {
        let idx = makeIndex(score: 0)
        XCTAssertEqual(idx.tier, .bad)
    }

    // MARK: - starCount

    func test_starCount_matchesTier() {
        let cases: [(Int, Int)] = [(100, 5), (80, 4), (65, 3), (45, 2), (10, 1)]
        for (score, expected) in cases {
            let idx = makeIndex(score: score)
            XCTAssertEqual(idx.starCount, expected, "score=\(score)")
        }
    }

    // MARK: - Light Pollution Score

    func test_lightPollutionScore_bortle3_isMax() {
        // bortle=3: 30*(9-3)/6 = 30 → 満点
        let summary = makeNightSummary()
        let idx = computeIndex(nightSummary: summary, bortleClass: 3.0)
        XCTAssertEqual(idx.lightPollutionScore, 30)
    }

    func test_lightPollutionScore_bortle6_isMid() {
        // bortle=6: 30*(9-6)/6 = 15
        let summary = makeNightSummary()
        let idx = computeIndex(nightSummary: summary, bortleClass: 6.0)
        XCTAssertEqual(idx.lightPollutionScore, 15)
    }

    func test_lightPollutionScore_bortle9_isZero() {
        // bortle=9: 30*(9-9)/6 = 0
        let summary = makeNightSummary()
        let idx = computeIndex(nightSummary: summary, bortleClass: 9.0)
        XCTAssertEqual(idx.lightPollutionScore, 0)
    }

    func test_lightPollutionScore_nilBortle_isZero() {
        let summary = makeNightSummary()
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.lightPollutionScore, 0)
    }

    // MARK: - Constellation Score (暗時間 × 月照度)

    func test_constellationScore_maxDarkHours_newMoon() {
        // darkEvents=25 → 6.25h > 6h → +20pts
        // phase=0 (新月) → illumination=0 < 0.05 → +10pts
        // total = 30 (上限)
        let summary = makeIdealDarkSummary()
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.constellationScore, 30)
    }

    func test_constellationScore_noDarkHours_fullMoon() {
        // darkEvents=0 → 0h → +0pts
        // phase=0.5 (満月) → illumination=1.0 ≥ 0.30 → +0pts
        let summary = makeNightSummary(moonPhase: 0.5)
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.constellationScore, 0)
    }

    func test_constellationScore_moderateDark_newMoon() {
        // darkEvents=9 → 2.25h > 2h → +9pts
        // phase=0 → illumination=0 < 0.05 → +10pts → total=19
        let summary = makeNightSummary(darkEventCount: 9)
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.constellationScore, 19)
    }

    func test_constellationScore_smallDark_waxingGibbousMoon() {
        // darkEvents=1 → 0.25h > 0h → +1pt（0–2時間は観測時間が短く最低点）
        // phase=0.3 → illumination=(1-cos(0.6π))/2 ≈ 0.655 → ≥0.30 → +0pts
        // total = 1
        let summary = makeNightSummary(darkEventCount: 1, moonPhase: 0.3)
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.constellationScore, 1)
    }

    // MARK: - Weather Score

    func test_weatherScore_bestConditions() {
        // cloud=10(<15)→+18
        // visibility=25000m(25km≥20)+spread=20(>15)→+8+2=10
        // precip=0, wcode=0(<45)→+6
        // gusts=15(<20), wind=5(<10)→+4
        // spread=20(>5)→+2
        // total = 40
        let summary = makeNightSummary()
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather)
        XCTAssertEqual(idx.weatherScore, 40)
    }

    func test_weatherScore_worstConditions() {
        // cloud=80(≥75)→+0
        // visibility=nil, spread=3(≤5)→+0
        // precip=1.0(≥0.5)→+0
        // gusts=nil→40(fallback), 40≥35 and not <50&&<35 combo → +0
        // spread=3(≤3)→+0
        let summary = makeNightSummary()
        let weather = makeWeather(cloud: 80, precip: 1.0, wind: 40, humidity: 90, dewpointSpread: 3)
        let idx = computeIndex(nightSummary: summary, weather: weather)
        XCTAssertEqual(idx.weatherScore, 0)
    }

    func test_weatherScore_moderateConditions() {
        // cloud=25(15-35)→+13
        // visibility=nil, spread=12(10-15)→+5(fallback)
        // precip=0.3(0.1-0.5)→+2
        // gusts=nil→15(fallback), gusts=15(<35), wind=15(<20)→+2
        // spread=12(>5)→+2
        // total = 24
        let summary = makeNightSummary()
        let weather = makeWeather(cloud: 25, precip: 0.3, wind: 15, humidity: 60, dewpointSpread: 12)
        let idx = computeIndex(nightSummary: summary, weather: weather)
        XCTAssertEqual(idx.weatherScore, 24)
    }

    // MARK: - Weather Score: 新指標テスト

    func test_weatherScore_layeredClouds_highOnly_lowsEffectiveCloud() {
        // low=0, mid=0, high=60 → effectiveCloud = 0×1.0 + 0×0.7 + 60×0.3 = 18
        // 総合雲量60%なら+7だが、実効雲量18%(<35)なら+13 になることを確認
        let summary = makeNightSummary()
        let weatherLayered = makeWeather(
            cloud: 60, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            cloudLow: 0, cloudMid: 0, cloudHigh: 60
        )
        let weatherTotal = makeWeather(
            cloud: 60, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20
        )
        let idxLayered = computeIndex(nightSummary: summary, weather: weatherLayered)
        let idxTotal = computeIndex(nightSummary: summary, weather: weatherTotal)
        // 層別データありの方が高いスコアになる（高層雲は半透明で遮断率低いため）
        XCTAssertGreaterThan(idxLayered.weatherScore, idxTotal.weatherScore,
            "高層雲のみの場合、層別加重の方が総合雲量より高スコアになるべき")
    }

    func test_weatherScore_transparencyScore_withExcellentVisibility() {
        // visibility=25km(≥20)→+8, spread=20(>15)→+2, 透明度 = 10点
        let summary = makeNightSummary()
        let withVis = makeWeather(
            cloud: 0, precip: 0, wind: 5, humidity: 30, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let withoutVis = makeWeather(
            cloud: 0, precip: 0, wind: 5, humidity: 30, dewpointSpread: 20,
            windGusts: 15
        )
        let idxWith = computeIndex(nightSummary: summary, weather: withVis)
        let idxWithout = computeIndex(nightSummary: summary, weather: withoutVis)
        // 視程データありの方が透明度スコアが高い（最大10点 vs フォールバック最大7点）
        XCTAssertGreaterThan(idxWith.weatherScore, idxWithout.weatherScore,
            "視程データありの方が高スコアになるべき")
    }

    func test_weatherScore_fogWeatherCode_reducesPrecipScore() {
        // precip=0 だが weatherCode=45(霧) → 降水スコアは1点のみ
        let summary = makeNightSummary()
        let fog = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 10,
            weatherCode: 45
        )
        let clear = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 10,
            weatherCode: 0
        )
        let idxFog = computeIndex(nightSummary: summary, weather: fog)
        let idxClear = computeIndex(nightSummary: summary, weather: clear)
        // 霧コードにより降水スコアが下がる（6点差）
        XCTAssertEqual(idxClear.weatherScore - idxFog.weatherScore, 5,
            "霧コード(45)で降水スコアが6点から1点に減るため差は5点")
    }

    func test_weatherScore_highWindGusts_reducesSeeingScore() {
        // avgWind=5(良好) でも windGusts=45(< 50 && avgWind < 35) → シーイング1点のみ
        let summary = makeNightSummary()
        let highGusts = makeWeather(
            cloud: 0, precip: 0, wind: 5, humidity: 30, dewpointSpread: 20,
            visibility: 25000, windGusts: 45
        )
        let lowGusts = makeWeather(
            cloud: 0, precip: 0, wind: 5, humidity: 30, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idxHigh = computeIndex(nightSummary: summary, weather: highGusts)
        let idxLow = computeIndex(nightSummary: summary, weather: lowGusts)
        // 突風差でシーイングスコアが4点→1点に落ちる
        XCTAssertEqual(idxLow.weatherScore - idxHigh.weatherScore, 3,
            "突風45km/hでシーイングが4点から1点に落ちるため差は3点")
    }

    func test_weatherScore_dewRisk_highRisk_zeroPoints() {
        // spread=2°C → 気温-露点差 < 3°C → 結露リスク高 → 露リスク0点
        let summary = makeNightSummary()
        let highRisk = makeWeather(
            cloud: 0, precip: 0, wind: 5, humidity: 95, dewpointSpread: 2,
            visibility: 25000, windGusts: 15
        )
        let lowRisk = makeWeather(
            cloud: 0, precip: 0, wind: 5, humidity: 30, dewpointSpread: 6,
            visibility: 25000, windGusts: 15
        )
        let idxHigh = computeIndex(nightSummary: summary, weather: highRisk)
        let idxLow = computeIndex(nightSummary: summary, weather: lowRisk)
        // spread=2 → 0点, spread=6 → 2点, 差は2点
        XCTAssertEqual(idxLow.weatherScore - idxHigh.weatherScore, 2,
            "露点差 6°C(2点) vs 2°C(0点) で差は2点")
    }

    // MARK: - compute() 統合テスト

    func test_compute_allBest_isExcellent() {
        // constellation=30(dark6h+20 + newMoon10), weather=40, lightPollution=30 → total=100
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertEqual(idx.score, 100)
        XCTAssertEqual(idx.tier, .excellent)
        XCTAssertTrue(idx.hasWeatherData)
        XCTAssertTrue(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_scaledFromConstellationAndLP() {
        // constellation=30(max), LP=30(max) → base=60, maxBase=60 → scaled=100
        let summary = makeIdealDarkSummary()
        let idx = computeIndex(nightSummary: summary, bortleClass: 3.0)
        XCTAssertEqual(idx.score, 100)
        XCTAssertFalse(idx.hasWeatherData)
        XCTAssertTrue(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_noLP_scaledFromConstellationOnly() {
        // constellation=30(max), LP=0 → base=30, maxBase=30 → scaled=100
        let summary = makeIdealDarkSummary()
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.score, 100)
        XCTAssertFalse(idx.hasWeatherData)
        XCTAssertFalse(idx.hasLightPollutionData)
    }

    func test_compute_overcast_isBad() {
        // 星座・光害が高くても雲量80%→cap34→観測困難
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(cloud: 80, precip: 0, wind: 5, humidity: 60, dewpointSpread: 10)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertLessThanOrEqual(idx.score, 34)
        XCTAssertEqual(idx.tier, .bad)
    }

    func test_compute_heavyRain_isBad() {
        // 降水1.0mm→cap34→観測困難
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(cloud: 90, precip: 1.0, wind: 10, humidity: 80, dewpointSpread: 5)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertLessThanOrEqual(idx.score, 34)
        XCTAssertEqual(idx.tier, .bad)
    }

    func test_compute_fog_isBad() {
        // 霧(WMO 45)→cap34→観測困難（雲量が少なくても霧は視程をほぼゼロにする）
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(cloud: 20, precip: 0, wind: 3, humidity: 95, dewpointSpread: 1,
                                  weatherCode: 45)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertLessThanOrEqual(idx.score, 34)
        XCTAssertEqual(idx.tier, .bad)
    }

    func test_compute_eveningRainThenClear_isNotBad() {
        // 夜間13時間のうち4時間が雨(31%)、残り9時間が快晴
        // → 暗時間帯(hour 0-6)のうち4時間(hour 0-3)が雨、3時間(hour 4-6)が晴れ
        // → ブロック率 4/7 = 57% ≥ 50% → poorCap 発動（cap49）→「観測困難」にはならない
        let summary = makeIdealDarkSummary()
        // makeNightSummary と同じ epoch 0 を基準にして hour-of-day を一致させる
        let base = Date(timeIntervalSince1970: 0)
        var hours: [HourlyWeather] = []
        for i in 0..<4 {
            hours.append(makeHourlyWeather(
                base: base,
                hourOffset: i,
                cloud: 95,
                precip: 2.0,
                wind: 10,
                humidity: 90,
                dewpoint: 14,
                weatherCode: 63
            ))
        }
        for i in 4..<13 {
            hours.append(makeHourlyWeather(
                base: base,
                hourOffset: i,
                cloud: 10,
                precip: 0,
                wind: 5,
                humidity: 40,
                dewpoint: 5,
                weatherCode: 0
            ))
        }
        let weather = DayWeatherSummary(date: base, nighttimeHours: hours)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertGreaterThan(idx.score, 34, "夕方の雨が止んで晴れる夜(31%ブロック)は「観測困難」にならないべき")
        XCTAssertNotEqual(idx.tier, .bad)
    }

    func test_compute_mostlyOvercast_isBad() {
        // 夜間13時間のうち9時間が完全曇り
        // → 暗時間帯(hour 0-6)の全7時間が曇り(hour 0-6 が完全ブロック)
        // → ブロック率 100% → cap34 → 「観測困難」になる
        let summary = makeIdealDarkSummary()
        let base = Date(timeIntervalSince1970: 0)
        var hours: [HourlyWeather] = []
        for i in 0..<9 {
            hours.append(makeHourlyWeather(
                base: base,
                hourOffset: i,
                cloud: 90,
                precip: 0,
                wind: 5,
                humidity: 60,
                dewpoint: 10,
                weatherCode: 3
            ))
        }
        for i in 9..<13 {
            hours.append(makeHourlyWeather(
                base: base,
                hourOffset: i,
                cloud: 10,
                precip: 0,
                wind: 5,
                humidity: 40,
                dewpoint: 5,
                weatherCode: 0
            ))
        }
        let weather = DayWeatherSummary(date: base, nighttimeHours: hours)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        // 暗時間帯(hour 0-6)の全7時間が曇り → ブロック率100% → cap34
        XCTAssertLessThanOrEqual(idx.score, 34, "暗時間帯の全時間が曇りなら「観測困難」になるべき")
        XCTAssertEqual(idx.tier, .bad)
    }

    func test_compute_noWeather_partialScore_scalesCorrectly() {
        // constellation: darkEvents=9 → 2.25h → +9pts, moonPhase=0.5 → illumination=1.0 → +0pts → 9pts
        // LP: bortle=6 → 30*(9-6)/6 = 15pts
        // base=9+15=24, maxBase=60 → scaled = Int(24/60*100) = 40
        let summary = makeNightSummary(darkEventCount: 9, moonPhase: 0.5)
        let idx = computeIndex(nightSummary: summary, bortleClass: 6.0)
        let expected = Int(Double(9 + 15) / 60.0 * 100.0)
        XCTAssertEqual(idx.score, expected)
    }
}
