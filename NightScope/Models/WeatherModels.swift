import Foundation

private enum CloudCoverWeight {
    static let low = 1.0
    static let mid = 0.7
    static let high = 0.3

    static func effective(low: Double, mid: Double, high: Double) -> Double {
        min(100, low * Self.low + mid * Self.mid + high * Self.high)
    }
}

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

    /// 層別加重実効雲量 = low×1.0 + mid×0.7 + high×0.3
    /// 3層データが揃わない場合は総合雲量にフォールバック
    var effectiveCloudCover: Double {
        guard let low = cloudCoverLowPercent,
              let mid = cloudCoverMidPercent,
              let high = cloudCoverHighPercent else {
            return cloudCoverPercent
        }
        return CloudCoverWeight.effective(low: low, mid: mid, high: high)
    }
}

struct DayWeatherSummary {
    private struct Aggregates {
        let cloudSum: Double
        let windSum: Double
        let humiditySum: Double
        let dewpointSpreadSum: Double
        let maxPrecipitation: Double
        let minTemperature: Double
        let maxWeatherCode: Int

        let visibilitySum: Double
        let visibilityCount: Int
        let maxWindGusts: Double?

        let cloudLowSum: Double
        let cloudLowCount: Int
        let cloudMidSum: Double
        let cloudMidCount: Int
        let cloudHighSum: Double
        let cloudHighCount: Int

        let wind500Sum: Double
        let wind500Count: Int

        static func build(from hours: [HourlyWeather]) -> Aggregates {
            var cloudSum = 0.0
            var windSum = 0.0
            var humiditySum = 0.0
            var dewpointSpreadSum = 0.0
            var maxPrecipitation = -Double.infinity
            var minTemperature = Double.infinity
            var maxWeatherCode = 0

            var visibilitySum = 0.0
            var visibilityCount = 0
            var maxWindGusts: Double?

            var cloudLowSum = 0.0
            var cloudLowCount = 0
            var cloudMidSum = 0.0
            var cloudMidCount = 0
            var cloudHighSum = 0.0
            var cloudHighCount = 0

            var wind500Sum = 0.0
            var wind500Count = 0

            for hour in hours {
                cloudSum += hour.cloudCoverPercent
                windSum += hour.windSpeedKmh
                humiditySum += hour.humidityPercent
                dewpointSpreadSum += (hour.temperatureCelsius - hour.dewpointCelsius)
                maxPrecipitation = max(maxPrecipitation, hour.precipitationMM)
                minTemperature = min(minTemperature, hour.temperatureCelsius)
                maxWeatherCode = max(maxWeatherCode, hour.weatherCode)

                if let visibility = hour.visibilityMeters {
                    visibilitySum += visibility
                    visibilityCount += 1
                }
                if let gust = hour.windGustsKmh {
                    maxWindGusts = max(maxWindGusts ?? -Double.infinity, gust)
                }
                if let low = hour.cloudCoverLowPercent {
                    cloudLowSum += low
                    cloudLowCount += 1
                }
                if let mid = hour.cloudCoverMidPercent {
                    cloudMidSum += mid
                    cloudMidCount += 1
                }
                if let high = hour.cloudCoverHighPercent {
                    cloudHighSum += high
                    cloudHighCount += 1
                }
                if let wind500 = hour.windSpeedKmh500hpa {
                    wind500Sum += wind500
                    wind500Count += 1
                }
            }

            return Aggregates(
                cloudSum: cloudSum,
                windSum: windSum,
                humiditySum: humiditySum,
                dewpointSpreadSum: dewpointSpreadSum,
                maxPrecipitation: maxPrecipitation,
                minTemperature: minTemperature,
                maxWeatherCode: maxWeatherCode,
                visibilitySum: visibilitySum,
                visibilityCount: visibilityCount,
                maxWindGusts: maxWindGusts,
                cloudLowSum: cloudLowSum,
                cloudLowCount: cloudLowCount,
                cloudMidSum: cloudMidSum,
                cloudMidCount: cloudMidCount,
                cloudHighSum: cloudHighSum,
                cloudHighCount: cloudHighCount,
                wind500Sum: wind500Sum,
                wind500Count: wind500Count
            )
        }
    }

    let date: Date
    let nighttimeHours: [HourlyWeather]

    private let aggregates: Aggregates

    init(date: Date, nighttimeHours: [HourlyWeather]) {
        self.date = date
        self.nighttimeHours = nighttimeHours
        self.aggregates = Aggregates.build(from: nighttimeHours)
    }

    var avgCloudCover: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return aggregates.cloudSum / Double(nighttimeHours.count)
    }

    var maxPrecipitation: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return aggregates.maxPrecipitation
    }

    var avgWindSpeed: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return aggregates.windSum / Double(nighttimeHours.count)
    }

    var minTemperature: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return aggregates.minTemperature
    }

    var avgHumidity: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return aggregates.humiditySum / Double(nighttimeHours.count)
    }

    /// 気温と露点の平均差（大気の透明度の代理指標・結露リスク評価）
    var avgDewpointSpread: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return aggregates.dewpointSpreadSum / Double(nighttimeHours.count)
    }

    /// 低層雲量（< 2km）の夜間平均。データなし時は nil
    var avgCloudCoverLow: Double? {
        guard aggregates.cloudLowCount > 0 else { return nil }
        return aggregates.cloudLowSum / Double(aggregates.cloudLowCount)
    }

    /// 中層雲量（2-6km）の夜間平均。データなし時は nil
    var avgCloudCoverMid: Double? {
        guard aggregates.cloudMidCount > 0 else { return nil }
        return aggregates.cloudMidSum / Double(aggregates.cloudMidCount)
    }

    /// 高層雲量（> 6km）の夜間平均。データなし時は nil
    var avgCloudCoverHigh: Double? {
        guard aggregates.cloudHighCount > 0 else { return nil }
        return aggregates.cloudHighSum / Double(aggregates.cloudHighCount)
    }

    /// 層別加重実効雲量 = low×1.0 + mid×0.7 + high×0.3
    /// 根拠: 低層雲は不透明（遮断率1.0）、高層雲は半透明（遮断率0.3）
    /// 3層すべてのデータが揃わない場合は nil（フォールバック用）
    var effectiveCloudCover: Double? {
        guard let low = avgCloudCoverLow,
              let mid = avgCloudCoverMid,
              let high = avgCloudCoverHigh else { return nil }
        return CloudCoverWeight.effective(low: low, mid: mid, high: high)
    }

    /// 視程の夜間平均（メートル）。データなし時は nil
    var avgVisibilityMeters: Double? {
        guard aggregates.visibilityCount > 0 else { return nil }
        return aggregates.visibilitySum / Double(aggregates.visibilityCount)
    }

    /// 夜間の最大突風速度（km/h）。データなし時は nil
    var maxWindGusts: Double? {
        aggregates.maxWindGusts
    }

    /// 500hPa（≈ 5.5km）の夜間平均風速（km/h）。データなし時は nil
    var avgWindSpeed500hpa: Double? {
        guard aggregates.wind500Count > 0 else { return nil }
        return aggregates.wind500Sum / Double(aggregates.wind500Count)
    }

    var cloudLabel: String {
        switch avgCloudCover {
        case 0..<15:  return L10n.tr("快晴")
        case 15..<35: return L10n.tr("晴れ")
        case 35..<55: return L10n.tr("薄雲")
        case 55..<75: return L10n.tr("曇り")
        default:      return L10n.tr("厚い雲")
        }
    }

    /// 夜間で最も深刻な天気コード（WMO）
    var representativeWeatherCode: Int {
        aggregates.maxWeatherCode
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
        case 0:        return L10n.tr("快晴")
        case 1:        return L10n.tr("晴れ")
        case 2:        return L10n.tr("晴れ時々曇り")
        case 3:        return L10n.tr("曇り")
        case 45, 48:   return L10n.tr("霧")
        case 51, 53, 55: return L10n.tr("霧雨")
        case 61:       return L10n.tr("小雨")
        case 63:       return L10n.tr("雨")
        case 65:       return L10n.tr("大雨")
        case 71:       return L10n.tr("小雪")
        case 73:       return L10n.tr("雪")
        case 75:       return L10n.tr("大雪")
        case 77:       return L10n.tr("細雪")
        case 80, 81, 82: return L10n.tr("にわか雨")
        case 85, 86:   return L10n.tr("にわか雪")
        case 95:       return L10n.tr("雷雨")
        case 96, 99:   return L10n.tr("雷雨（ひょう）")
        default:       return L10n.tr("不明")
        }
    }
}
