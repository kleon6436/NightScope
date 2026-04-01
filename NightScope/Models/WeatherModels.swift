import Foundation

// MARK: - Models

struct HourlyWeather {
    let date: Date
    let temperatureCelsius: Double
    let cloudCoverPercent: Double
    let precipitationMM: Double
    let windSpeedKmh: Double
    let humidityPercent: Double
    let dewpointCelsius: Double
    let weatherCode: Int
    /// 視程（メートル）。大気透明度の直接測定値。nil = データなし
    let visibilityMeters: Double?
    /// 瞬間最大風速（km/h）。シーイング評価に使用。nil = データなし
    let windGustsKmh: Double?
    /// 低層雲量（< 2km）0-100%。nil = データなし
    let cloudCoverLowPercent: Double?
    /// 中層雲量（2-6km）0-100%。nil = データなし
    let cloudCoverMidPercent: Double?
    /// 高層雲量（> 6km）0-100%。nil = データなし
    let cloudCoverHighPercent: Double?
    /// 500hPa 高度（≈ 5.5km）の風速（km/h）。シーイング評価に使用。nil = データなし
    let windSpeedKmh500hpa: Double?
}

struct DayWeatherSummary {
    let date: Date
    let nighttimeHours: [HourlyWeather]

    private var nighttimeTotals: (cloud: Double, wind: Double, humidity: Double, dewpointSpread: Double, maxPrecip: Double, minTemp: Double) {
        nighttimeHours.reduce((0, 0, 0, 0, -Double.infinity, Double.infinity)) { acc, h in
            (acc.0 + h.cloudCoverPercent,
             acc.1 + h.windSpeedKmh,
             acc.2 + h.humidityPercent,
             acc.3 + (h.temperatureCelsius - h.dewpointCelsius),
             max(acc.4, h.precipitationMM),
             min(acc.5, h.temperatureCelsius))
        }
    }

    var avgCloudCover: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.cloud / Double(nighttimeHours.count)
    }

    var maxPrecipitation: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.maxPrecip
    }

    var avgWindSpeed: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.wind / Double(nighttimeHours.count)
    }

    var minTemperature: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.minTemp
    }

    var avgHumidity: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.humidity / Double(nighttimeHours.count)
    }

    /// 気温と露点の平均差（大気の透明度の代理指標・結露リスク評価）
    var avgDewpointSpread: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.dewpointSpread / Double(nighttimeHours.count)
    }

    /// 低層雲量（< 2km）の夜間平均。データなし時は nil
    var avgCloudCoverLow: Double? {
        let values = nighttimeHours.compactMap(\.cloudCoverLowPercent)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 中層雲量（2-6km）の夜間平均。データなし時は nil
    var avgCloudCoverMid: Double? {
        let values = nighttimeHours.compactMap(\.cloudCoverMidPercent)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 高層雲量（> 6km）の夜間平均。データなし時は nil
    var avgCloudCoverHigh: Double? {
        let values = nighttimeHours.compactMap(\.cloudCoverHighPercent)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 層別加重実効雲量 = low×1.0 + mid×0.7 + high×0.3
    /// 根拠: 低層雲は不透明（遮断率1.0）、高層雲は半透明（遮断率0.3）
    /// 3層すべてのデータが揃わない場合は nil（フォールバック用）
    var effectiveCloudCover: Double? {
        guard let low = avgCloudCoverLow,
              let mid = avgCloudCoverMid,
              let high = avgCloudCoverHigh else { return nil }
        return low * 1.0 + mid * 0.7 + high * 0.3
    }

    /// 視程の夜間平均（メートル）。データなし時は nil
    var avgVisibilityMeters: Double? {
        let values = nighttimeHours.compactMap(\.visibilityMeters)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 夜間の最大突風速度（km/h）。データなし時は nil
    var maxWindGusts: Double? {
        let values = nighttimeHours.compactMap(\.windGustsKmh)
        guard !values.isEmpty else { return nil }
        return values.max()
    }

    /// 500hPa（≈ 5.5km）の夜間平均風速（km/h）。データなし時は nil
    var avgWindSpeed500hpa: Double? {
        let values = nighttimeHours.compactMap(\.windSpeedKmh500hpa)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var cloudLabel: String {
        switch avgCloudCover {
        case 0..<15:  return "快晴"
        case 15..<35: return "晴れ"
        case 35..<55: return "薄雲"
        case 55..<75: return "曇り"
        default:      return "厚い雲"
        }
    }

    /// 夜間で最も深刻な天気コード（WMO）
    var representativeWeatherCode: Int {
        nighttimeHours.map(\.weatherCode).max() ?? 0
    }

    var weatherIconName: String {
        let code = representativeWeatherCode
        switch code {
        case 0:          return AppIcons.Weather.sunMaxFill
        case 1:          return AppIcons.Weather.sunMaxFill
        case 2:          return AppIcons.Weather.cloudSunFill
        case 3:          return AppIcons.Weather.cloudFill
        case 45, 48:     return AppIcons.Weather.cloudFogFill
        case 51, 53, 55: return AppIcons.Weather.cloudDrizzleFill
        case 61:         return AppIcons.Weather.cloudRainFill
        case 63:         return AppIcons.Weather.cloudRainFill
        case 65:         return AppIcons.Weather.cloudHeavyrainFill
        case 71, 73, 75: return AppIcons.Weather.cloudSnowFill
        case 77:         return AppIcons.Weather.cloudSnowFill
        case 80, 81, 82: return AppIcons.Weather.cloudRainFill
        case 85, 86:     return AppIcons.Weather.cloudSnowFill
        case 95:         return AppIcons.Weather.cloudBoltFill
        case 96, 99:     return AppIcons.Weather.cloudBoltRainFill
        default:         return AppIcons.Weather.cloudFill
        }
    }

    var weatherLabel: String {
        let code = representativeWeatherCode
        switch code {
        case 0:        return "快晴"
        case 1:        return "晴れ"
        case 2:        return "晴れ時々曇り"
        case 3:        return "曇り"
        case 45, 48:   return "霧"
        case 51, 53, 55: return "霧雨"
        case 61:       return "小雨"
        case 63:       return "雨"
        case 65:       return "大雨"
        case 71:       return "小雪"
        case 73:       return "雪"
        case 75:       return "大雪"
        case 77:       return "細雪"
        case 80, 81, 82: return "にわか雨"
        case 85, 86:   return "にわか雪"
        case 95:       return "雷雨"
        case 96, 99:   return "雷雨（ひょう）"
        default:       return "不明"
        }
    }
}
