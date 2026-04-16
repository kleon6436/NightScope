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
        /// - badCap: 全暗時間が観測不可（雨・高雲量等）→ 「観測困難」キャップ
        /// - poorCap: 以下いずれかで「不向き」キャップを発動
        ///   (a) 暗時間の1/4以上が観測不可（時間帯集中の悪天候）
        ///   (b) 気象スコアが閾値未満（平均的に観測条件が悪い）
        ///   (a)(b) の OR 条件にすることで、どちらか一方の評価軸だけで
        ///   キャップが発動しない抜け穴を防ぎつつ、両評価軸が整合している場合は
        ///   正しいスコアを保持する（スコア逆転現象の防止）。
        static let blockedFractionForBadCap = 1.0
        static let blockedFractionForPoorCap = 0.25

        /// 天候キャップ後の上限スコア
        static let badCapScore = 34
        static let poorCapScore = 49

        /// poorCap 発動の気象スコア閾値（0–40）
        /// - 根拠: 40点満点の50%未満は「平均的な観測条件を下回る」とみなす。
        ///   気象スコア20以上 かつ 暗時間帯のブロック率25%未満なら、キャップを掛けず
        ///   スコアをそのまま反映する。逆にスコアが低い場合は時間帯分布に関わらず
        ///   「不向き」と判断することで、高スコアが不当に低評価になる逆転を防ぐ。
        static let weatherScoreForPoorCap = 20

        /// 観測可能時間スコア閾値（条件: `hours > threshold`）
        /// - 根拠: 観測時間が長いほど対象天体の追尾・再構図・雲待ちが可能になる。
        /// - しきい値ごとの意図:
        ///   - `>4h`: 主要対象を十分に追跡できる実用上の満点帯（15点）
        ///   - `>2h`: 複数対象を狙える実用帯（10点）
        ///   - `>1h`: 1対象中心の短時間観測（6点）
        ///   - `>0h`: 最低限の観測機会がある（2点）
        static let viewingHoursThresholds: [(Double, Int)] = [
            // >4h: 長時間追尾が可能で機材セットアップの元が取れる
            (4, 15),
            // >2h: 観測計画として成立しやすい時間幅
            (2, 10),
            // >1h: 限定的だが観測は可能
            (1, 6),
            // >0h: わずかな観測窓を最低点として評価
            (0, 2)
        ]

        /// 銀河中心高度スコア閾値（条件: `altitude > threshold`）
        /// - 根拠: 高度が高いほど大気減光・地物遮蔽の影響が減り、像質が改善する。
        /// - しきい値ごとの意図:
        ///   - `>45°`: 大気路程が短く最良帯（10点）
        ///   - `>30°`: 実用的に高品質（7点）
        ///   - `>15°`: 観測は可能だが減光影響が増える（4点）
        ///   - `>5°`: 地平線近傍の最低限帯（1点）
        static let altitudeThresholds: [(Double, Int)] = [
            // >45°: 大気影響が比較的小さく見通しが良い
            (45, 10),
            // >30°: 実用観測として安定
            (30, 7),
            // >15°: 観測可能下限に近い
            (15, 4),
            // >5°: 低空で条件は厳しいが機会はある
            (5, 1)
        ]

        /// 暗時間スコア閾値（条件: `darkHours > threshold`）
        /// - 根拠: 天文薄明中の暗時間は観測可能性そのものを規定する。
        /// - しきい値ごとの意図:
        ///   - `>6h`: 冬季等の長い暗夜（20点）
        ///   - `>4h`: 十分な暗時間（15点）
        ///   - `>2h`: 限定的だが有効な暗時間（9点）
        ///   - `<=2h`: 実用性が低いため既定1点（呼び出し側で指定）
        static let darkHoursThresholds: [(Double, Int)] = [
            // >6h: ほぼフルセッション可能
            (6, 20),
            // >4h: 観測計画を立てやすい
            (4, 15),
            // >2h: 短時間計画向け
            (2, 9)
        ]

        /// 月照度スコア閾値（条件: `illumination < threshold`）
        /// - 根拠: Krisciunas & Schaefer (1991) に基づき、照度増加で空輝度が非線形に悪化。
        /// - しきい値ごとの意図:
        ///   - `<0.05`: 新月近傍で空輝度影響が最小（10点）
        ///   - `<0.15`: 繊月で影響は増えるが観測余地あり（6点）
        ///   - `<0.30`: 影響大で限定的（2点）
        ///   - `>=0.30`: 上弦以降は観測困難（既定0点）
        static let moonIlluminationThresholds: [(Double, Int)] = [
            // 新月近傍
            (0.05, 10),
            // 繊月帯
            (0.15, 6),
            // 半月手前まで
            (0.30, 2)
        ]

        /// 雲量スコア閾値（条件: `effectiveCloud < threshold`）
        /// - 根拠: 有効雲量が増えるほど星像の遮断率が急激に増加する。
        /// - しきい値ごとの意図:
        ///   - `<15%`: ほぼ快晴（18点）
        ///   - `<35%`: 晴れ優勢（13点）
        ///   - `<55%`: 薄雲混在（7点）
        ///   - `<75%`: 曇り優勢だが断続的観測余地あり（2点）
        ///   - `>=75%`: 実質観測不可（既定0点）
        static let cloudThresholds: [(Double, Int)] = [
            // 快晴〜ほぼ快晴
            (15, 18),
            // 晴れ優勢
            (35, 13),
            // 薄雲帯
            (55, 7),
            // 曇り優勢
            (75, 2)
        ]

        /// 視程スコア閾値（条件: `visibilityKm >= threshold`）
        /// - 根拠: 視程はエアロゾル・水蒸気量を反映し、限界等級に直結する。
        /// - しきい値ごとの意図:
        ///   - `>=20km`: NOAA「非常に良好」相当（8点）
        ///   - `>=10km`: 良好（5点）
        ///   - `>=5km`: 可視だが透明度不足（2点）
        static let visibilityThresholds: [(Double, Int)] = [
            // 非常に良好
            (20, 8),
            // 良好
            (10, 5),
            // 最低限
            (5, 2)
        ]

        /// 露点差ボーナス閾値（条件: `spread > threshold`）
        /// - 根拠: 露点差が大きいほど大気が乾燥し、透明度が向上しやすい。
        /// - しきい値ごとの意図:
        ///   - `>15°C`: 非常に乾燥（+2点）
        ///   - `>10°C`: 乾燥傾向（+1点）
        static let dewpointDrynessBonusThresholds: [(Double, Int)] = [
            // 非常に乾燥
            (15, 2),
            // 乾燥傾向
            (10, 1)
        ]

        /// 視程データ欠損時の透明度フォールバック閾値（条件: `spread > threshold`）
        /// - 根拠: 露点差のみ評価のため過大評価を避け、上限を7点に制限。
        /// - しきい値ごとの意図:
        ///   - `>15°C`: 欠損時の最大評価（7点）
        ///   - `>10°C`: 中程度（5点）
        ///   - `>5°C`: 最低限の透明度余地（2点）
        static let spreadOnlyTransparencyThresholds: [(Double, Int)] = [
            // 欠損時の最大評価
            (15, 7),
            // 中程度
            (10, 5),
            // 最低限
            (5, 2)
        ]

        /// 地表シーイング（上空風あり時）
        /// 条件: `gusts < maxGust && averageWind < maxWind`
        /// - 根拠: 上空風を別評価するため、地表側は0–2点の補助評価に限定。
        static let surfaceSeeingUpperWindRules: [(maxGust: Double, maxWind: Double, score: Int)] = [
            // 穏やかな風況
            (20, 10, 2),
            // やや不安定
            (35, 20, 1)
        ]

        /// 地表シーイング（上空風なし時のフォールバック）
        /// 条件: `gusts < maxGust && averageWind < maxWind`
        /// - 根拠: 上空情報欠損時は地表風のみで 0–4点を段階評価。
        static let surfaceSeeingFallbackRules: [(maxGust: Double, maxWind: Double, score: Int)] = [
            // 良好
            (20, 10, 4),
            // 中程度
            (35, 20, 2),
            // 観測は可能だが像質は不安定
            (50, 35, 1)
        ]
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

        if let weather = weather,
           nightSummary.hasReliableWeatherData(nighttimeHours: weather.nighttimeHours) {
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
                nonWeatherBase: constellation + lightPollution,
                weatherScore: weatherPts,
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
        // 観測可能時間 (0–15 pts)
        let hours = nightSummary.totalViewingHours
        let viewingScore = scoreByGreaterThan(hours, thresholds: Constants.viewingHoursThresholds)

        // 銀河系中心の最大高度 (0–10 pts)
        let alt = nightSummary.maxAltitude ?? 0
        let altitudeScore = scoreByGreaterThan(alt, thresholds: Constants.altitudeThresholds)

        return min(viewingScore + altitudeScore, 25)
    }

    // MARK: - Sky Score (0–30)

    private static func computeConstellationScore(nightSummary: NightSummary) -> Int {
        var score = 0

        // 天文薄明中の暗い時間 (0–20 pts)
        // 根拠: 天文薄明（太陽高度 < -18°、IAU標準）のみを有効な観測時間として評価。
        //       0–2時間は銀河の高度変化を追跡できず実用的な観測が難しいため最低点（1点）。
        let darkHours = nightSummary.totalDarkHours
        guard darkHours > 0 else { return 0 }

        score += scoreByGreaterThan(
            darkHours,
            thresholds: Constants.darkHoursThresholds,
            defaultScore: 1 // 0–2時間: 観測時間が極端に短く実用性が低い
        )

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

        let moonScoreWhenVisible = scoreByLessThan(
            illumination,
            thresholds: Constants.moonIlluminationThresholds,
            defaultScore: 0
        )
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
        return scoreByLessThan(effectiveCloud, thresholds: Constants.cloudThresholds, defaultScore: 0)
    }

    // b. 大気透明度 (0–10 pts)
    // 根拠: 視程(visibility)は大気中のエアロゾル・水蒸気量を反映し、制限等級（限界等級）に直結する。
    //       視程 ≥ 20km = NOAAの「非常に良好」基準。6等星以上の観測が期待できる条件。
    //       視程データなし時は露点差のみで評価（最大7点に制限してデータなしのペナルティを反映）。
    private static func computeTransparencyScore(weather: DayWeatherSummary) -> Int {
        let spread = weather.avgDewpointSpread

        if let vis = weather.avgVisibilityMeters {
            let visibilityKm = vis / 1000.0
            return visibilityBaseTransparencyScore(visibilityKm: visibilityKm)
            + dewpointDrynessBonusScore(spread: spread)
        }

        // フォールバック: 視程データなし時は露点差のみで 0–7 pts
        return transparencyScoreFromSpreadOnly(spread: spread)
    }

    // c. 降水 (0–6 pts)
    // 根拠: 霧(WMO コード 45, 48)は降水量ゼロでも視程をほぼゼロにし観測不可となる。
    //       51以上（霧雨・雨・雪）は即時観測中止に相当。
    //       isObservationBlocked と一貫して weatherCode >= 45 を観測不可として扱う。
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
        // weatherCode >= 45（霧・霧雨・雨・雪・雷雨）は降水量に関わらず観測不可
        // isObservationBlocked と同じ基準で一貫して 0 点
        if weatherCode >= 45 {
            return 0
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
            let surfaceScore = surfaceSeeingScoreForUpperWind(averageWind: averageWind, gusts: gusts)

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
        return surfaceSeeingScoreFallback(averageWind: averageWind, gusts: gusts)
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

    private static func visibilityBaseTransparencyScore(visibilityKm: Double) -> Int {
        scoreByGreaterOrEqual(visibilityKm, thresholds: Constants.visibilityThresholds, defaultScore: 0)
    }

    /// 露点差による補正 (0–2 pts): 乾燥した大気ほど透明度が高い
    private static func dewpointDrynessBonusScore(spread: Double) -> Int {
        scoreByGreaterThan(spread, thresholds: Constants.dewpointDrynessBonusThresholds, defaultScore: 0)
    }

    private static func transparencyScoreFromSpreadOnly(spread: Double) -> Int {
        scoreByGreaterThan(spread, thresholds: Constants.spreadOnlyTransparencyThresholds, defaultScore: 0)
    }

    private static func scoreByGreaterThan(
        _ value: Double,
        thresholds: [(threshold: Double, score: Int)],
        defaultScore: Int = 0
    ) -> Int {
        for item in thresholds where value > item.threshold {
            return item.score
        }
        return defaultScore
    }

    private static func scoreByLessThan(
        _ value: Double,
        thresholds: [(threshold: Double, score: Int)],
        defaultScore: Int = 0
    ) -> Int {
        for item in thresholds where value < item.threshold {
            return item.score
        }
        return defaultScore
    }

    private static func scoreByGreaterOrEqual(
        _ value: Double,
        thresholds: [(threshold: Double, score: Int)],
        defaultScore: Int = 0
    ) -> Int {
        for item in thresholds where value >= item.threshold {
            return item.score
        }
        return defaultScore
    }

    private static func surfaceSeeingScoreForUpperWind(averageWind: Double, gusts: Double) -> Int {
        scoreByDualUpperBounds(
            gusts: gusts,
            averageWind: averageWind,
            rules: Constants.surfaceSeeingUpperWindRules,
            defaultScore: 0
        )
    }

    private static func surfaceSeeingScoreFallback(averageWind: Double, gusts: Double) -> Int {
        scoreByDualUpperBounds(
            gusts: gusts,
            averageWind: averageWind,
            rules: Constants.surfaceSeeingFallbackRules,
            defaultScore: 0
        )
    }

    private static func scoreByDualUpperBounds(
        gusts: Double,
        averageWind: Double,
        rules: [(maxGust: Double, maxWind: Double, score: Int)],
        defaultScore: Int = 0
    ) -> Int {
        for rule in rules where gusts < rule.maxGust && averageWind < rule.maxWind {
            return rule.score
        }
        return defaultScore
    }

    // MARK: - Cap helpers

    private static func applyBadWeatherCap(
        to score: Int,
        nonWeatherBase: Int,
        weatherScore: Int,
        nightSummary: NightSummary,
        weather: DayWeatherSummary
    ) -> Int {
        let darkWeatherHours = weatherHoursDuringDarkTime(nightSummary: nightSummary, weather: weather)
        guard !darkWeatherHours.isEmpty else { return score }

        let blockedCount = darkWeatherHours.filter { isObservationBlocked($0) }.count
        let blockedFraction = Double(blockedCount) / Double(darkWeatherHours.count)

        if blockedFraction >= Constants.blockedFractionForBadCap {
            // 全暗時間帯が観測不可 = weatherAwareRangeText も "" を返す状態
            // 気象に依存しない要素（星座+光害）を 0-badCapScore にスケールして
            // 場所・季節ごとの「本来の潜在力」を反映した値にする
            let maxNonWeather = maxConstellationScore + maxLightPollutionScore  // 60
            let scaled = Int(Double(nonWeatherBase) / Double(maxNonWeather) * Double(Constants.badCapScore))
            return min(score, scaled)
        }
        // poorCap: 暗時間帯の1/4以上がブロック OR 気象スコアが閾値未満
        // → どちらか一方でも「観測に向かない条件」とみなす
        if blockedFraction >= Constants.blockedFractionForPoorCap
            || weatherScore < Constants.weatherScoreForPoorCap {
            return min(score, Constants.poorCapScore)  // 不向き
        }
        return score
    }

    private static func weatherHoursDuringDarkTime(
        nightSummary: NightSummary,
        weather: DayWeatherSummary
    ) -> [HourlyWeather] {
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: nightSummary.timeZone)
        let darkHourSet = Set(nightSummary.events
            .filter { $0.isDark }
            .compactMap { calendar.dateInterval(of: .hour, for: $0.date)?.start })

        return weather.nighttimeHours.filter { hour in
            guard let hourStart = calendar.dateInterval(of: .hour, for: hour.date)?.start else {
                return false
            }
            return darkHourSet.contains(hourStart)
        }
    }

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
