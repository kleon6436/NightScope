import Foundation

struct StarGazingIndex {
    private enum Constants {
        /// 光害スコア最大値。全体100点中の30点（旧10点から引き上げ）。
        /// 根拠: 光害（Bortle値）は観測可能な天体の限界等級を直接決定し、
        ///       全観測条件の中で最も根本的な制約要因となる。
        static let lightPollutionMaxScore = 30
        /// Bortle スケールの最悪クラス（都市中心部）
        static let bortleWorstClass: Double = 9.0
        /// このクラス以下は満点（日本の最暗空相当）
        static let bortleBestClass: Double = 3.0

        /// 暗時間帯の観測不可割合しきい値
        static let blockedFractionForBadCap = 1.0
        static let blockedFractionForPoorCap = 0.75

        /// 天候キャップ後の上限スコア
        static let badCapScore = 34
        static let poorCapScore = 49
    }

    // MARK: - 各スコアの最大値（UI表示用）
    static let maxMilkyWayScore       = 25
    static let maxConstellationScore  = 30
    static let maxWeatherScore        = 40
    static let maxLightPollutionScore = Constants.lightPollutionMaxScore  // 30

    let score: Int
    let milkyWayScore: Int       // 0–25 (表示のみ、合計スコアに含まない)
    let constellationScore: Int  // 0–30
    let weatherScore: Int        // 0–40 (気象データなし時は 0)
    let lightPollutionScore: Int // 0–30 (未取得時は 0)
    let hasWeatherData: Bool
    let hasLightPollutionData: Bool

    enum Tier {
        case excellent, good, fair, poor, bad
    }

    var tier: Tier {
        switch score {
        case 90...100: return .excellent
        case 75..<90:  return .good
        case 50..<75:  return .fair
        case 35..<50:  return .poor
        default:       return .bad
        }
    }

    var label: String {
        switch tier {
        case .excellent: return "絶好の星空"
        case .good:      return "良い星空"
        case .fair:      return "普通"
        case .poor:      return "不向き"
        case .bad:       return "観測困難"
        }
    }

    var starCount: Int {
        switch tier {
        case .excellent: return 5
        case .good:      return 4
        case .fair:      return 3
        case .poor:      return 2
        case .bad:       return 1
        }
    }

    // MARK: - Computation

    static func compute(
        nightSummary: NightSummary,
        weather: DayWeatherSummary?,
        bortleClass: Double?
    ) -> StarGazingIndex {
        let mw = computeMilkyWayScore(nightSummary: nightSummary)
        let constellation = computeConstellationScore(nightSummary: nightSummary)
        let lightPollution = computeLightPollutionScore(bortleClass: bortleClass)
        let hasLP = bortleClass != nil

        if let weather = weather {
            let weatherPts = computeWeatherScore(weather: weather)
            // 合計: 星座(0-30) + 気象(0-40) + 光害(0-30) = 0-100
            let rawTotal = min(100, constellation + weatherPts + lightPollution)
            // 天文薄明（isDark）の時間帯のみを対象に観測不可割合を計算してキャップを設定
            // 根拠: weatherAwareRangeText は isDark なイベントのみを評価する。
            //       全13時間（18:00-06:59）を使うと夕方や明け方の悪天候が
            //       暗い時間帯の評価を歪め「観測可能時間あり＆観測困難」の矛盾が生じる。
            //       isDark な時間帯に対応する天候のみを評価することで整合性を保つ。
            let cappedTotal = applyBadWeatherCap(
                to: rawTotal,
                nightSummary: nightSummary,
                weather: weather
            )

            return makeIndex(
                score: cappedTotal,
                milkyWayScore: mw,
                constellationScore: constellation,
                weatherScore: weatherPts,
                lightPollutionScore: lightPollution,
                hasWeatherData: true,
                hasLightPollutionData: hasLP
            )
        } else {
            // 気象データなし: 星座(0-30) + 光害(0-30) を 60点満点として換算
            let maxBase = hasLP ? 60 : 30
            let base = constellation + lightPollution
            let scaled = min(100, Int(Double(base) / Double(maxBase) * 100.0))
            return makeIndex(
                score: scaled,
                milkyWayScore: mw,
                constellationScore: constellation,
                weatherScore: 0,
                lightPollutionScore: lightPollution,
                hasWeatherData: false,
                hasLightPollutionData: hasLP
            )
        }
    }

    private static func makeIndex(
        score: Int,
        milkyWayScore: Int,
        constellationScore: Int,
        weatherScore: Int,
        lightPollutionScore: Int,
        hasWeatherData: Bool,
        hasLightPollutionData: Bool
    ) -> StarGazingIndex {
        StarGazingIndex(
            score: score,
            milkyWayScore: milkyWayScore,
            constellationScore: constellationScore,
            weatherScore: weatherScore,
            lightPollutionScore: lightPollutionScore,
            hasWeatherData: hasWeatherData,
            hasLightPollutionData: hasLightPollutionData
        )
    }

    // MARK: - Milky Way Score (0–25) — 表示専用

    private static func computeMilkyWayScore(nightSummary: NightSummary) -> Int {
        var score = 0

        // 観測可能時間 (0–15 pts)
        let hours = nightSummary.totalViewingHours
        if hours > 4 {
            score += 15
        } else if hours > 2 {
            score += 10
        } else if hours > 1 {
            score += 6
        } else if hours > 0 {
            score += 2
        }

        // 銀河系中心の最大高度 (0–10 pts)
        let alt = nightSummary.maxAltitude ?? 0
        if alt > 45 {
            score += 10
        } else if alt > 30 {
            score += 7
        } else if alt > 15 {
            score += 4
        } else if alt > 5 {
            score += 1
        }

        return min(score, 25)
    }

    // MARK: - Sky Score (0–30)

    private static func computeConstellationScore(nightSummary: NightSummary) -> Int {
        var score = 0

        // 天文薄明中の暗い時間 (0–20 pts)
        // 根拠: 天文薄明（太陽高度 < -18°、IAU標準）のみを有効な観測時間として評価。
        //       0–2時間は銀河の高度変化を追跡できず実用的な観測が難しいため最低点（1点）。
        let darkHours = nightSummary.totalDarkHours
        guard darkHours > 0 else { return 0 }

        if darkHours > 6 {
            score += 20
        } else if darkHours > 4 {
            score += 15
        } else if darkHours > 2 {
            score += 9
        } else {
            score += 1  // 0–2時間: 観測時間が極端に短く実用性が低い
        }

        // 月の照明度 (0–10 pts) × 月が地平線上にある割合
        // illumination = (1 - cos(phase × 2π)) / 2
        // phase=0 → 新月(illumination=0), phase=0.5 → 満月(illumination=1)
        //
        // 根拠: Krisciunas & Schaefer (1991) の実測データに基づく非線形評価。
        //   illumination 0.15以上では空輝度が自然夜空の10倍以上増加し天の川はほぼ消失。
        //   illumination 0.30以上（上弦付近）では空輝度が自然夜空の30〜50倍に達し観測不可。
        // moonFraction: 天文薄明中に月が地平線上にある割合（0=ずっと地平線以下, 1=常に地平線上）
        //   月が地平線以下の時間帯は照明影響なし（満点10点相当）として加重平均する。
        let phase = nightSummary.moonPhaseAtMidnight
        let illumination = (1.0 - cos(phase * 2.0 * .pi)) / 2.0
        let moonFraction = nightSummary.moonAboveHorizonFractionDuringDark

        let moonScoreWhenVisible: Int
        if illumination < 0.05 {
            moonScoreWhenVisible = 10  // 新月付近: 最良条件
        } else if illumination < 0.15 {
            moonScoreWhenVisible = 6   // 繊月: 空輝度が数倍に増加
        } else if illumination < 0.30 {
            moonScoreWhenVisible = 2   // 三日月以降: 空輝度が10倍超、天の川はほぼ消失
        } else {
            moonScoreWhenVisible = 0   // 上弦〜満月: 観測困難
        }
        // 月が地平線以下の時間帯は理想条件(10点)として扱い加重平均
        let weightedMoonScore = Int(round(Double(moonScoreWhenVisible) * moonFraction
                                          + 10.0 * (1.0 - moonFraction)))
        score += weightedMoonScore

        return min(score, 30)
    }

    // MARK: - Weather Score (0–40)

    private static func computeWeatherScore(weather: DayWeatherSummary) -> Int {
        let score = computeCloudScore(weather: weather)
        + computeTransparencyScore(weather: weather)
        + computePrecipitationScore(weather: weather)
        + computeSeeingScore(weather: weather)
        + computeDewRiskScore(weather: weather)
        return min(score, 40)
    }

    // a. 雲量 (0–18 pts)
    // 根拠: 低層雲(< 2km)は不透明で星を完全遮断。高層雲(> 6km)は巻雲等の氷晶雲で半透明。
    //       層別加重実効雲量 = low×1.0 + mid×0.7 + high×0.3 で精度向上。
    //       層別データなし時は総合雲量にフォールバック。
    private static func computeCloudScore(weather: DayWeatherSummary) -> Int {
        let effectiveCloud = weather.effectiveCloudCover ?? weather.avgCloudCover
        if effectiveCloud < 15 {
            return 18
        }
        if effectiveCloud < 35 {
            return 13
        }
        if effectiveCloud < 55 {
            return 7
        }
        if effectiveCloud < 75 {
            return 2
        }
        return 0
    }

    // b. 大気透明度 (0–10 pts)
    // 根拠: 視程(visibility)は大気中のエアロゾル・水蒸気量を反映し、制限等級（限界等級）に直結する。
    //       視程 ≥ 20km = NOAAの「非常に良好」基準。6等星以上の観測が期待できる条件。
    //       視程データなし時は露点差のみで評価（最大7点に制限してデータなしのペナルティを反映）。
    private static func computeTransparencyScore(weather: DayWeatherSummary) -> Int {
        let spread = weather.avgDewpointSpread

        if let vis = weather.avgVisibilityMeters {
            var score = 0
            let visibilityKm = vis / 1000.0
            if visibilityKm >= 20 {
                score += 8
            } else if visibilityKm >= 10 {
                score += 5
            } else if visibilityKm >= 5 {
                score += 2
            }
            // 露点差による補正 (0–2 pts): 乾燥した大気ほど透明度が高い
            if spread > 15 {
                score += 2
            } else if spread > 10 {
                score += 1
            }
            return score
        }

        // フォールバック: 視程データなし時は露点差のみで 0–7 pts
        if spread > 15 {
            return 7
        }
        if spread > 10 {
            return 5
        }
        if spread > 5 {
            return 2
        }
        return 0
    }

    // c. 降水 (0–6 pts)
    // 根拠: 霧(WMO コード 45, 48)は降水量ゼロでも視程をほぼゼロにし観測不可となる。
    //       51以上（霧雨・雨・雪）は即時観測中止に相当。
    private static func computePrecipitationScore(weather: DayWeatherSummary) -> Int {
        let precipitation = weather.maxPrecipitation
        let weatherCode = weather.representativeWeatherCode

        if precipitation == 0 && weatherCode < 45 {
            return 6
        }
        if precipitation == 0 && weatherCode <= 48 {
            // 霧のみ: 視程がほぼゼロのため最低点
            return 1
        }
        if precipitation < 0.1 {
            return 4
        }
        if precipitation < 0.5 {
            return 2
        }
        return 0
    }

    // d. シーイング・風 (0–4 pts)
    // 根拠: 天文シーイング（大気の揺らぎ）は地表から対流圏全体の乱流で決まる。
    //       地表突風データ(0–4pts): 突風（瞬間最大風速）は地表乱流の直接指標。
    //       上空風データ(500hPa ≈ 5.5km)がある場合は地表+上空の複合評価(各0–2pts)に切り替え。
    //       上空風なし時は地表突風のみで評価（フォールバック）。
    private static func computeSeeingScore(weather: DayWeatherSummary) -> Int {
        let averageWind = weather.avgWindSpeed
        let gusts = weather.maxWindGusts ?? averageWind

        if let upperWind = weather.avgWindSpeed500hpa {
            // 地表 (0–2pts) + 上空 (0–2pts) の複合シーイング評価
            let surfaceScore: Int
            if gusts < 20 && averageWind < 10 {
                surfaceScore = 2
            } else if gusts < 35 && averageWind < 20 {
                surfaceScore = 1
            } else {
                surfaceScore = 0
            }

            // 500hPa ≈ 5.5km。30km/h未満は良好、60km/h以上は乱流強く観測困難
            let upperScore: Int
            if upperWind < 30 {
                upperScore = 2
            } else if upperWind < 60 {
                upperScore = 1
            } else {
                upperScore = 0
            }
            return min(4, surfaceScore + upperScore)
        }

        // フォールバック: 地表突風データのみで評価（最大4点）
        if gusts < 20 && averageWind < 10 {
            return 4
        }
        if gusts < 35 && averageWind < 20 {
            return 2
        }
        if gusts < 50 && averageWind < 35 {
            return 1
        }
        return 0
    }

    // e. 露リスク (0–2 pts)
    // 根拠: 気温と露点の差（露点差）< 3°C で相対湿度が約90%以上となり、
    //       光学部品（レンズ・反射鏡）への結露が発生する。旧「湿度スコア」を置き換え。
    private static func computeDewRiskScore(weather: DayWeatherSummary) -> Int {
        let dewpointSpread = weather.avgDewpointSpread
        if dewpointSpread > 5 {
            return 2
        }
        if dewpointSpread > 3 {
            return 1
        }
        return 0
    }

    // MARK: - Cap helpers

    private static func applyBadWeatherCap(
        to score: Int,
        nightSummary: NightSummary,
        weather: DayWeatherSummary
    ) -> Int {
        let darkWeatherHours = weatherHoursDuringDarkTime(nightSummary: nightSummary, weather: weather)
        guard !darkWeatherHours.isEmpty else { return score }

        let blockedCount = darkWeatherHours.filter { isObservationBlocked($0) }.count
        let blockedFraction = Double(blockedCount) / Double(darkWeatherHours.count)

        if blockedFraction >= Constants.blockedFractionForBadCap {
            // 全暗時間帯が観測不可 = weatherAwareRangeText も "" を返す状態
            return min(score, Constants.badCapScore)  // 観測困難
        }
        if blockedFraction >= Constants.blockedFractionForPoorCap {
            // 暗時間帯の75%以上が観測不可（小さな観測窓のみ）
            return min(score, Constants.poorCapScore)  // 不向き
        }
        return score
    }

    private static func weatherHoursDuringDarkTime(
        nightSummary: NightSummary,
        weather: DayWeatherSummary
    ) -> [HourlyWeather] {
        let calendar = Calendar.current
        let darkHourSet = Set(nightSummary.events
            .filter { $0.isDark }
            .map { calendar.component(.hour, from: $0.date) })

        return weather.nighttimeHours.filter { hour in
            darkHourSet.contains(calendar.component(.hour, from: hour.date))
        }
    }

    /// 1時間分の実効雲量（AstroModels.effectiveCloudCover と同一ロジック）
    /// 観測不可時間かどうかを判定（passesWeatherFilter の条件と同一）
    /// 根拠: 観測可能時間帯表示と同じ判定基準を用いることで、
    ///       「時間帯表示あり」と「星空指数のキャップ」の整合性を保つ。
    private static func isObservationBlocked(_ hour: HourlyWeather) -> Bool {
        return hour.effectiveCloudCover >= 75
            || hour.precipitationMM >= 0.1
            || hour.weatherCode >= 45
    }

    // MARK: - Light Pollution Score (0–30)

    private static func computeLightPollutionScore(bortleClass: Double?) -> Int {
        guard let bortle = bortleClass else { return 0 }
        // 日本の最暗空は Bortle 3 程度。3 以下はすべて満点 30。
        // Bortle 9 で 0 点になるよう線形スケール（3〜9 の範囲）。
        // 変換元データ: Falchi et al. (2016, Science Advances) World Atlas 2015
        //
        // 線形マッピングの根拠:
        //   Bortle スケールは各クラス間が約3倍の輝度差（対数スケール）で定義されている。
        //   したがって Bortle → スコアの線形変換は、実際の輝度に対して対数スケールの
        //   変換と等価であり、等しい輝度倍率の変化を等しいスコア変化として扱う。
        //   限界等級も Bortle にほぼ線形に対応するため、実用上の評価としても適切。
        let range = Constants.bortleWorstClass - Constants.bortleBestClass
        return max(0, min(Constants.lightPollutionMaxScore,
                          Int(round(Double(Constants.lightPollutionMaxScore) * (Constants.bortleWorstClass - bortle) / range))))
    }
}
