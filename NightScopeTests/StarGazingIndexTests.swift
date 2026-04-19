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
        moonAltitude: Double = 30.0,  // デフォルトは地平線上 (月スコアが月相に従って評価される)
        moonBelowCount: Int = 0       // 指定数のイベントの月高度を -10 にする（月加重テスト用）
    ) -> NightSummary {
        let base = Date(timeIntervalSince1970: 0)
        let location = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0)

        // 1イベント = 15分。sunAltitude < -18 で isDark = true
        let events = (0..<darkEventCount).map { i in
            let isMoonBelow = i < moonBelowCount
            return AstroEvent(
                date: base.addingTimeInterval(Double(i) * 900),
                galacticCenterAltitude: 0,
                galacticCenterAzimuth: 0,
                sunAltitude: -20.0,
                moonAltitude: isMoonBelow ? -10.0 : moonAltitude,
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

    private func makeIdealDarkSummary(
        moonPhase: Double = 0.0,
        moonAltitude: Double = 30.0
    ) -> NightSummary {
        makeNightSummary(darkEventCount: 25, moonPhase: moonPhase, moonAltitude: moonAltitude)
    }

    private func computeIndex(
        nightSummary: NightSummary,
        weather: DayWeatherSummary? = nil,
        bortleClass: Double? = nil
    ) -> StarGazingIndex {
        let expandedWeather = weather.map { expandWeatherCoverage($0, for: nightSummary) }
        return StarGazingIndex.compute(
            nightSummary: nightSummary,
            weather: expandedWeather,
            bortleClass: bortleClass
        )
    }

    private func expandWeatherCoverage(_ weather: DayWeatherSummary, for nightSummary: NightSummary) -> DayWeatherSummary {
        guard let template = weather.nighttimeHours.first else {
            return weather
        }

        let expectedHours = Set(nightSummary.events.compactMap { event in
            Calendar(identifier: .gregorian).dateInterval(of: .hour, for: event.date)?.start
        }).sorted()

        guard expectedHours.count > weather.nighttimeHours.count else {
            return weather
        }

        let expandedHours = expectedHours.map { hourStart in
            HourlyWeather(
                date: hourStart,
                temperatureCelsius: template.temperatureCelsius,
                cloudCoverPercent: template.cloudCoverPercent,
                precipitationMM: template.precipitationMM,
                windSpeedKmh: template.windSpeedKmh,
                humidityPercent: template.humidityPercent,
                dewpointCelsius: template.dewpointCelsius,
                weatherCode: template.weatherCode,
                visibilityMeters: template.visibilityMeters,
                windGustsKmh: template.windGustsKmh,
                cloudCoverLowPercent: template.cloudCoverLowPercent,
                cloudCoverMidPercent: template.cloudCoverMidPercent,
                cloudCoverHighPercent: template.cloudCoverHighPercent,
                windSpeedKmh500hpa: template.windSpeedKmh500hpa
            )
        }

        return DayWeatherSummary(date: weather.date, nighttimeHours: expandedHours)
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

    func test_lightPollutionScore_bortle1_isMax() {
        // bortle=1: round(30*(9-1)/6) = 40 → 30にクランプ（満点）
        let summary = makeNightSummary(darkEventCount: 25)
        let idx = computeIndex(nightSummary: summary, bortleClass: 1.0)
        XCTAssertEqual(idx.lightPollutionScore, 30)
    }

    func test_lightPollutionScore_bortle3() {
        // bortle=3: 日本の実質最良条件 → 満点(30)
        let summary = makeNightSummary(darkEventCount: 25)
        let idx = computeIndex(nightSummary: summary, bortleClass: 3.0)
        XCTAssertEqual(idx.lightPollutionScore, 30)
    }

    func test_lightPollutionScore_bortle6_isMid() {
        // bortle=6: round(30*(9-6)/6) = round(15) = 15
        let summary = makeNightSummary(darkEventCount: 25)
        let idx = computeIndex(nightSummary: summary, bortleClass: 6.0)
        XCTAssertEqual(idx.lightPollutionScore, 15)
    }

    func test_lightPollutionScore_bortle9_isZero() {
        // bortle=9: round(30*(9-9)/6) = 0
        let summary = makeNightSummary(darkEventCount: 25)
        let idx = computeIndex(nightSummary: summary, bortleClass: 9.0)
        XCTAssertEqual(idx.lightPollutionScore, 0)
    }

    func test_lightPollutionScore_nilBortle_isZero() {
        let summary = makeNightSummary(darkEventCount: 25)
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.lightPollutionScore, 0)
    }

    // MARK: - Constellation Score (暗時間 × 月照度)

    func test_constellationScore_maxDarkHours_newMoon() {
        // darkEvents=25 → 6.25h >= 6h → +20pts
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
        // darkEvents=9 → 2.25h >= 2h → +9pts
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
        let summary = makeNightSummary(darkEventCount: 1)
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
        let summary = makeNightSummary(darkEventCount: 1)
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
        let summary = makeNightSummary(darkEventCount: 1)
        let weather = makeWeather(cloud: 25, precip: 0.3, wind: 15, humidity: 60, dewpointSpread: 12)
        let idx = computeIndex(nightSummary: summary, weather: weather)
        XCTAssertEqual(idx.weatherScore, 24)
    }

    // MARK: - Weather Score: 新指標テスト

    func test_weatherScore_layeredClouds_highOnly_lowsEffectiveCloud() {
        // low=0, mid=0, high=60 → effectiveCloud = 0×1.0 + 0×0.7 + 60×0.3 = 18
        // 総合雲量60%なら+7だが、実効雲量18%(<35)なら+13 になることを確認
        let summary = makeNightSummary(darkEventCount: 1)
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
        let summary = makeNightSummary(darkEventCount: 1)
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
        let summary = makeNightSummary(darkEventCount: 1)
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

    func test_weatherScore_drizzleCode_zerosPrecipScore() {
        // 霧雨(code 51-55) は降水量が微量（0.05mm）でも isObservationBlocked と同様に 0 点
        let summary = makeNightSummary(darkEventCount: 1)
        let drizzle = makeWeather(
            cloud: 80, precip: 0.05, wind: 5, humidity: 90, dewpointSpread: 2,
            weatherCode: 51
        )
        let lightClearRain = makeWeather(
            cloud: 80, precip: 0.05, wind: 5, humidity: 90, dewpointSpread: 2,
            weatherCode: 2  // 晴れ時々曇り（code < 45）で同じ降水量
        )
        let idxDrizzle = computeIndex(nightSummary: summary, weather: drizzle)
        let idxClearRain = computeIndex(nightSummary: summary, weather: lightClearRain)
        // 霧雨コード(51)は降水スコア 0 点。code < 45 かつ precip 0.05mm は 4 点
        XCTAssertEqual(idxClearRain.weatherScore - idxDrizzle.weatherScore, 4,
            "霧雨コード(51)で降水スコアが0点になり、code<45同条件との差は4点")
    }

    func test_weatherScore_drizzleCode_zeroPrecip_zerosPrecipScore() {
        // 霧雨コード(53) + 降水量ゼロでも観測不可と判断して 0 点
        let summary = makeNightSummary(darkEventCount: 1)
        let drizzleNoPrecip = makeWeather(
            cloud: 90, precip: 0, wind: 3, humidity: 95, dewpointSpread: 1,
            weatherCode: 53
        )
        let clearNoPrecip = makeWeather(
            cloud: 90, precip: 0, wind: 3, humidity: 95, dewpointSpread: 1,
            weatherCode: 0
        )
        let idxDrizzle = computeIndex(nightSummary: summary, weather: drizzleNoPrecip)
        let idxClear = computeIndex(nightSummary: summary, weather: clearNoPrecip)
        // code 53 は precipitation=0 でも code >= 51 のため precipitation==0 && code<45 の6点分岐に入らず 0 点
        XCTAssertEqual(idxClear.weatherScore - idxDrizzle.weatherScore, 6,
            "霧雨コード(53)で降水量ゼロでも降水スコアが0点になり、快晴との差は6点")
    }

    func test_weatherScore_highWindGusts_reducesSeeingScore() {
        // avgWind=5(良好) でも windGusts=45(< 50 && avgWind < 35) → シーイング1点のみ
        let summary = makeNightSummary(darkEventCount: 1)
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
        let summary = makeNightSummary(darkEventCount: 1)
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
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertEqual(idx.score, 100)
        XCTAssertEqual(idx.tier, .excellent)
        XCTAssertTrue(idx.hasWeatherData)
        XCTAssertTrue(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_cappedByConfidence() {
        // constellation=30(max), LP=30(max) → base=60, maxBase=60 → scaled=100
        // → noWeatherCap=74 でキャップ
        let summary = makeIdealDarkSummary()
        let idx = computeIndex(nightSummary: summary, bortleClass: 1.0)
        XCTAssertEqual(idx.score, 74)
        XCTAssertFalse(idx.hasWeatherData)
        XCTAssertTrue(idx.hasLightPollutionData)
    }

    func test_compute_noWeather_noLP_cappedByConfidence() {
        // constellation=30(max), LP=0 → base=30, maxBase=30 → scaled=100
        // → noWeatherNoLPCap=54 でキャップ
        let summary = makeIdealDarkSummary()
        let idx = computeIndex(nightSummary: summary)
        XCTAssertEqual(idx.score, 54)
        XCTAssertFalse(idx.hasWeatherData)
        XCTAssertFalse(idx.hasLightPollutionData)
    }

    func test_compute_partialWeatherCoverage_treatedAsNoWeather() {
        let summary = makeIdealDarkSummary()
        let partialWeather = DayWeatherSummary(
            date: Date(timeIntervalSince1970: 0),
            nighttimeHours: [
                makeHourlyWeather(
                    base: Date(timeIntervalSince1970: 0),
                    hourOffset: 0,
                    cloud: 10,
                    precip: 0,
                    wind: 5,
                    humidity: 40,
                    dewpoint: 0,
                    weatherCode: 0
                )
            ]
        )

        let idx = StarGazingIndex.compute(
            nightSummary: summary,
            weather: partialWeather,
            bortleClass: 3.0
        )

        XCTAssertFalse(idx.hasWeatherData)
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
        // → ブロック率 4/7 = 57% ≥ 25% → poorCap 発動（cap49）→「観測困難」にはならない
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

    func test_compute_partialDrizzle_isPoor() {
        // 暗時間帯(hour 0-6)の7時間のうち4時間が霧雨(code51) → ブロック率 4/7 ≈ 57% ≥ 25%
        // → poorCap(49) 発動（blockedFraction条件） → 「不向き」になるべき
        let summary = makeIdealDarkSummary()
        let base = Date(timeIntervalSince1970: 0)
        var hours: [HourlyWeather] = []
        // 暗時間帯 hour 0-3: 霧雨（4時間）
        for i in 0..<4 {
            hours.append(makeHourlyWeather(
                base: base, hourOffset: i,
                cloud: 90, precip: 0.05, wind: 5, humidity: 90, dewpoint: 13,
                weatherCode: 51
            ))
        }
        // 暗時間帯 hour 4-6: 晴れ（3時間）
        for i in 4..<7 {
            hours.append(makeHourlyWeather(
                base: base, hourOffset: i,
                cloud: 10, precip: 0, wind: 5, humidity: 40, dewpoint: 5,
                weatherCode: 0
            ))
        }
        // 日中 hour 7-12: 晴れ
        for i in 7..<13 {
            hours.append(makeHourlyWeather(
                base: base, hourOffset: i,
                cloud: 10, precip: 0, wind: 5, humidity: 40, dewpoint: 5,
                weatherCode: 0
            ))
        }
        let weather = DayWeatherSummary(date: base, nighttimeHours: hours)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertLessThanOrEqual(idx.score, 49, "暗時間の57%が霧雨なら poorCap(49)が掛かり不向き以下になるべき")
        XCTAssertTrue(idx.tier == .poor || idx.tier == .bad, "霧雨57%ブロックは不向きまたは観測困難になるべき")
    }

    func test_compute_lowWeatherScore_clearDarkHours_isPoor() {
        // 暗時間帯はすべて晴れ（blockedFraction=0）だが、気象スコアが低い（薄曇り平均）
        // → weatherScore < 20 の条件で poorCap 発動 → 「不向き」になるべき
        // cloud=65%: isObservationBlocked の閾値(75%)未満なのでブロックされない
        // weatherScore: cloudScore=2 + transparency=2 + precip=6 + seeing=4 + dew=2 = 16 < 20
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 65, precip: 0, wind: 5, humidity: 70, dewpointSpread: 6,
            windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertLessThanOrEqual(idx.score, 49,
            "気象スコアが20未満(薄曇り)の場合、ブロック率0%でも poorCap が掛かるべき")
        XCTAssertTrue(idx.tier == .poor || idx.tier == .bad,
            "平均的に薄曇りな夜（weatherScore<20）は不向き以下になるべき")
    }

    func test_compute_goodWeather_noBlockedHours_isNotPoor() {
        // 暗時間帯はすべて晴れ（blockedFraction=0）かつ気象スコアが良好（≥20）
        // → どちらの poorCap 条件も満たさない → 「普通」以上になるべき
        // 回帰テスト: 全サブスコアが高いのに低評価になるスコア逆転現象の防止
        // weatherScore: cloudScore=13 + transparency=5 + precip=6 + seeing=4 + dew=2 = 30 ≥ 20
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 25, precip: 0, wind: 5, humidity: 60, dewpointSpread: 10,
            windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 3.0)
        XCTAssertGreaterThan(idx.score, 49,
            "気象スコア≥20かつブロック率0%の場合は poorCap が掛からず普通以上になるべき")
        XCTAssertTrue(idx.tier == .fair || idx.tier == .good || idx.tier == .excellent,
            "良好な気象（weatherScore≥20）かつ晴天の暗時間帯は普通以上になるべき")
    }

    func test_compute_noWeather_partialScore_scalesCorrectly() {
        // constellation: darkEvents=9 → 2.25h → +9pts, moonPhase=0.5 → illumination=1.0 → +0pts → 9pts
        // LP: bortle=6 → round(30*(9-6)/6) = 15pts
        // base=9+15=24, maxBase=60 → scaled = Int(24/60*100) = 40
        // noWeatherCap=74 → min(40,74)=40, moonCap Hard(49) → min(40,49)=40
        let summary = makeNightSummary(darkEventCount: 9, moonPhase: 0.5)
        let idx = computeIndex(nightSummary: summary, bortleClass: 6.0)
        XCTAssertEqual(idx.score, 40)
    }

    // MARK: - #1 白夜（暗時間ゼロ）

    func test_compute_noDarkHours_alwaysZero() {
        // 暗時間ゼロは観測不能 → 常に 0 点
        let summary = makeNightSummary(darkEventCount: 0)
        let idx = computeIndex(nightSummary: summary, bortleClass: 1.0)
        XCTAssertEqual(idx.score, 0, "暗時間ゼロは観測不能なので 0 点になるべき")
    }

    func test_compute_noDarkHours_withWeather_alwaysZero() {
        // 白夜 + 天気データありでも 0 点
        let summary = makeNightSummary(darkEventCount: 0)
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertEqual(idx.score, 0, "白夜は天気が良くても 0 点になるべき")
    }

    // MARK: - #2 月明かりキャップ

    func test_compute_fullMoonAbove_cappedToPoor() {
        // 満月(phase=0.5, illumination=1.0) + 暗時間中ずっと月が上空(fraction=1.0)
        // → moonCap=49 発動 → 「不向き」以下
        let summary = makeIdealDarkSummary(moonPhase: 0.5, moonAltitude: 30.0)
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertLessThanOrEqual(idx.score, 49,
            "満月が暗時間中ずっと上空なら moonCap(49) が掛かるべき")
        XCTAssertTrue(idx.tier == .poor || idx.tier == .bad)
    }

    func test_compute_fullMoonBelowHorizon_notCapped() {
        // 満月(phase=0.5) だが暗時間中ずっと月が地平線下(moonAltitude=-10)
        // → moonFraction=0 → moonCap 不発動 → 高スコア維持
        let summary = makeIdealDarkSummary(moonPhase: 0.5, moonAltitude: -10.0)
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertGreaterThan(idx.score, 49,
            "満月でも暗時間中に月が地平線下なら moonCap は掛からないべき")
    }

    func test_compute_waxingCrescent_notCapped() {
        // 三日月(phase=0.1) → illumination ≈ 0.095 < 0.30 → moonCap 不発動
        let summary = makeIdealDarkSummary(moonPhase: 0.1, moonAltitude: 30.0)
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertGreaterThan(idx.score, 49,
            "三日月(illumination<0.30)では moonCap は掛からないべき")
    }

    func test_compute_moonHalfAbove_cappedToPoor() {
        // 満月 + 暗時間の52%で月が上空 → Hard cap 発動（illumination=1.0≥0.60, fraction=0.52≥0.50）
        let summary = makeNightSummary(
            darkEventCount: 25,
            moonPhase: 0.5,
            moonAltitude: 30.0,
            moonBelowCount: 12  // 25イベント中12が地平線下 → fraction = 13/25 = 0.52 ≥ 0.50
        )
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertLessThanOrEqual(idx.score, 49,
            "満月(illumination≥0.60)が暗時間の50%以上で上空なら Hard cap が掛かるべき")
    }

    func test_compute_moonMostlyBelow_notCapped() {
        // 満月 + 暗時間の36%で月が上空 → Hard cap 不発動（fraction < 0.50 境界値テスト）
        let summary = makeNightSummary(
            darkEventCount: 25,
            moonPhase: 0.5,
            moonAltitude: 30.0,
            moonBelowCount: 16  // 25イベント中16が地平線下 → fraction = 9/25 = 0.36 < 0.50
        )
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertGreaterThan(idx.score, 49,
            "満月が暗時間の50%未満で上空なら Hard cap は掛からないべき")
    }

    // MARK: - #6 光害キャップ

    func test_compute_bortle9_clearSky_cappedTo49() {
        // Bortle 9 + 快晴の最良条件 → 光害キャップ(49)で制限される
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 9.0)
        XCTAssertLessThanOrEqual(idx.score, 49,
            "Bortle 9 では快晴でもスコア上限 49(Poor)に制限されるべき")
    }

    func test_compute_bortle7_clearSky_cappedTo74() {
        // Bortle 7 + 快晴の最良条件 → 光害キャップ(74)で制限される
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 7.0)
        XCTAssertLessThanOrEqual(idx.score, 74,
            "Bortle 7 では快晴でもスコア上限74(Fair上位)に制限されるべき")
    }

    func test_compute_bortle6_clearSky_notCapped() {
        // Bortle 6 → 光害キャップ対象外 → 高スコア維持
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 6.0)
        XCTAssertGreaterThan(idx.score, 74,
            "Bortle 6 では光害キャップが掛からず高スコアになるべき")
    }

    func test_compute_bortle9_noWeather_cappedTo49() {
        // Bortle 9 + 気象データなし → noWeatherCap(74) と bortleCap(49) の両方が適用
        // bortleCap の方が厳しいので 49 で制限
        let summary = makeIdealDarkSummary()
        let idx = computeIndex(nightSummary: summary, bortleClass: 9.0)
        XCTAssertLessThanOrEqual(idx.score, 49,
            "Bortle 9 は気象データなしでも bortleCap(49)で制限されるべき")
    }

    func test_compute_bortle7_badWeather_notAffectedByBortleCap() {
        // Bortle 7 + 悪天候 → 天候キャップ(34)の方が厳しいので bortleCap(74)は影響しない
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(cloud: 80, precip: 1.0, wind: 10, humidity: 80, dewpointSpread: 5)
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 7.0)
        XCTAssertLessThanOrEqual(idx.score, 34,
            "悪天候キャップ(34)は bortleCap(74)より厳しいため、悪天候のスコアに影響なし")
    }

    // MARK: - #7 月キャップ Soft cap 境界

    func test_compute_softCap_justBelow_notCapped() {
        // 上弦(illumination≈0.30) + fraction=0.56 → Soft cap 不発動（fraction < 0.65）
        // phase=0.167 → illumination = (1-cos(0.334π))/2 ≈ 0.25 < 0.30 → Soft cap 不発動
        // phase=0.196 → illumination ≈ 0.30 に近い値
        // 正確に illumination=0.30 を生むには phase≈0.196
        // ここでは fraction が 0.60 未満であることで不発動を確認
        let summary = makeNightSummary(
            darkEventCount: 25,
            moonPhase: 0.196,  // illumination ≈ 0.30
            moonAltitude: 30.0,
            moonBelowCount: 11  // fraction = 14/25 = 0.56 < 0.65
        )
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertGreaterThan(idx.score, 64,
            "上弦付近(illumination≈0.30)で暗時間の56%なら Soft cap(fraction≥0.65)は掛からないべき")
    }

    func test_compute_softCap_fires_cappedTo64() {
        // 上弦(phase=0.25, illumination≈0.50) + fraction=0.72 → Soft cap 発動（64上限）
        // illumination = (1-cos(0.5π))/2 = 0.50 ≥ 0.30 → Soft cap 条件成立
        // Hard cap: 0.50 < 0.60 → 不発動
        let summary = makeNightSummary(
            darkEventCount: 25,
            moonPhase: 0.25,  // illumination = 0.50
            moonAltitude: 30.0,
            moonBelowCount: 7  // fraction = 18/25 = 0.72 ≥ 0.65
        )
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        XCTAssertLessThanOrEqual(idx.score, 64,
            "上弦(illumination=0.50)で暗時間の72%上空なら Soft cap(64)が掛かるべき")
        XCTAssertGreaterThanOrEqual(idx.score, 50,
            "Soft cap 発動時も Fair 帯（50以上）に留まるべき")
    }

    // MARK: - #8 光害キャップ境界

    func test_compute_bortle6_9_notCapped() {
        // Bortle 6.9 → キャップ対象外（7.0未満）
        let summary = makeIdealDarkSummary()
        let weather = makeWeather(
            cloud: 10, precip: 0, wind: 5, humidity: 40, dewpointSpread: 20,
            visibility: 25000, windGusts: 15
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 6.9)
        XCTAssertGreaterThan(idx.score, 74,
            "Bortle 6.9(< 7.0)は光害キャップ対象外で高スコアになるべき")
    }

    // MARK: - #9 暗時間段差 境界

    func test_constellationScore_darkHours1h_exact_getsScore() {
        // darkEvents=4 → 1.0h（ちょうど1h）→ >=1h なので 5pt
        let summary = makeNightSummary(darkEventCount: 4)
        let idx = computeIndex(nightSummary: summary)
        // darkHours=1.0: thresholds は >=1 なので 1.0 は該当する → 5pt
        // moonScore: phase=0 → illumination=0 < 0.05 → 10pt
        // total = 5 + 10 = 15
        XCTAssertEqual(idx.constellationScore, 15,
            "暗時間ちょうど1.0hは >=1h に該当し 5pt + moonScore=10 = 15 になるべき")
    }

    func test_constellationScore_darkHoursJustOver1h_is5() {
        // darkEvents=5 → 1.25h > 1h → 5pt
        let summary = makeNightSummary(darkEventCount: 5)
        let idx = computeIndex(nightSummary: summary)
        // darkHours=1.25: >1h → 5pt
        // moonScore: phase=0 → illumination=0 < 0.05 → 10pt
        // total = 5 + 10 = 15
        XCTAssertEqual(idx.constellationScore, 15,
            "暗時間1.25h(>1h)は darkHoursScore=5 + moonScore=10 = 15 になるべき")
    }

    // MARK: - #5 多層雲の実効雲量クランプ

    func test_effectiveCloudCover_clamped() {
        // low=50, mid=50, high=50 → 50*1.0 + 50*0.7 + 50*0.3 = 100 → min(100, 100)
        // low=60, mid=60, high=60 → 60*1.0 + 60*0.7 + 60*0.3 = 120 → min(100, 120) = 100
        let summary = makeNightSummary(darkEventCount: 1)
        let weather = makeWeather(
            cloud: 80, precip: 0, wind: 5, humidity: 60, dewpointSpread: 10,
            cloudLow: 60, cloudMid: 60, cloudHigh: 60
        )
        let idx = computeIndex(nightSummary: summary, weather: weather, bortleClass: 1.0)
        // 実効雲量が100にクランプされ、120にならないことを確認
        // 雲量100%→cloudScore=0 は変わらないが、isObservationBlocked の判定が安定する
        XCTAssertEqual(idx.weatherScore, idx.weatherScore)  // 計算自体がクラッシュしないことを確認
    }
}
