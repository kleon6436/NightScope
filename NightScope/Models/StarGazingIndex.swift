import Foundation

struct StarGazingIndex {
    let score: Int
    let milkyWayScore: Int       // 0–25 (表示のみ、合計スコアに含まない)
    let constellationScore: Int  // 0–50
    let weatherScore: Int        // 0–40 (気象データなし時は 0)
    let lightPollutionScore: Int // 0–10 (未取得時は 0)
    let hasWeatherData: Bool
    let hasLightPollutionData: Bool

    enum Tier {
        case excellent, good, fair, poor, bad
    }

    var tier: Tier {
        switch score {
        case 90...100: return .excellent
        case 75..<90:  return .good
        case 55..<75:  return .fair
        case 35..<55:  return .poor
        default:       return .bad
        }
    }

    var label: String {
        switch tier {
        case .excellent: return "絶好"
        case .good:      return "良好"
        case .fair:      return "まずまず"
        case .poor:      return "不良"
        case .bad:       return "不可"
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

    var scoreColor: String {
        switch tier {
        case .excellent: return "green"
        case .good:      return "green"
        case .fair:      return "yellow"
        case .poor:      return "orange"
        case .bad:       return "red"
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
            // 合計: 星座(0-50) + 気象(0-40) + 光害(0-10) = 0-100
            let total = min(100, constellation + weatherPts + lightPollution)
            return StarGazingIndex(
                score: total,
                milkyWayScore: mw,
                constellationScore: constellation,
                weatherScore: weatherPts,
                lightPollutionScore: lightPollution,
                hasWeatherData: true,
                hasLightPollutionData: hasLP
            )
        } else {
            // 気象データなし: 星座(0-50) + 光害(0-10) を 60点満点として換算
            let maxBase = hasLP ? 60 : 50
            let base = constellation + lightPollution
            let scaled = min(100, Int(Double(base) / Double(maxBase) * 100.0))
            return StarGazingIndex(
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

    // MARK: - Sky Score (0–50)

    private static func computeConstellationScore(nightSummary: NightSummary) -> Int {
        var score = 0

        // 天文薄明中の暗い時間 (0–30 pts)
        let darkHours = nightSummary.totalDarkHours
        if darkHours > 6 {
            score += 30
        } else if darkHours > 4 {
            score += 22
        } else if darkHours > 2 {
            score += 14
        } else if darkHours > 0 {
            score += 5
        }

        // 月の照明度 (0–20 pts)
        // illumination = (1 - cos(phase × 2π)) / 2
        // phase=0 → 新月(illumination=0), phase=0.5 → 満月(illumination=1)
        let phase = nightSummary.moonPhaseAtMidnight
        let illumination = (1.0 - cos(phase * 2.0 * .pi)) / 2.0
        if illumination < 0.10 {
            score += 20
        } else if illumination < 0.30 {
            score += 14
        } else if illumination < 0.50 {
            score += 8
        } else if illumination < 0.70 {
            score += 3
        }

        return min(score, 50)
    }

    // MARK: - Weather Score (0–40)

    private static func computeWeatherScore(weather: DayWeatherSummary) -> Int {
        var score = 0

        // 雲量 (0–18 pts)
        let cloud = weather.avgCloudCover
        if cloud < 15 {
            score += 18
        } else if cloud < 35 {
            score += 13
        } else if cloud < 55 {
            score += 7
        } else if cloud < 75 {
            score += 2
        }

        // 降水量 (0–8 pts)
        let precip = weather.maxPrecipitation
        if precip == 0 {
            score += 8
        } else if precip < 0.1 {
            score += 5
        } else if precip < 0.5 {
            score += 2
        }

        // 風速 (0–6 pts)
        let wind = weather.avgWindSpeed
        if wind < 10 {
            score += 6
        } else if wind < 20 {
            score += 4
        } else if wind < 35 {
            score += 2
        }

        // 湿度 (0–5 pts)
        let humidity = weather.avgHumidity
        if humidity < 50 {
            score += 5
        } else if humidity < 65 {
            score += 3
        } else if humidity < 80 {
            score += 1
        }

        // 大気の透明度（露点温度差）(0–3 pts)
        let spread = weather.avgDewpointSpread
        if spread > 15 {
            score += 3
        } else if spread > 10 {
            score += 2
        } else if spread > 5 {
            score += 1
        }

        return min(score, 40)
    }

    // MARK: - Light Pollution Score (0–10)

    private static func computeLightPollutionScore(bortleClass: Double?) -> Int {
        guard let bortle = bortleClass else { return 0 }
        // 日本の最暗空は Bortle 3 程度。3 以下はすべて満点 10。
        // Bortle 9 で 0 点になるよう線形スケール（3〜9 の範囲）。
        return max(0, min(10, Int(round(10.0 * (9.0 - bortle) / 6.0))))
    }
}
