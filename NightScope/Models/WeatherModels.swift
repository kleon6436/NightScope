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

    /// 気温と露点の平均差（大気の透明度の代理指標）
    var avgDewpointSpread: Double {
        guard !nighttimeHours.isEmpty else { return 0 }
        return nighttimeTotals.dewpointSpread / Double(nighttimeHours.count)
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
        case 0:          return "sun.max.fill"
        case 1:          return "sun.max.fill"
        case 2:          return "cloud.sun.fill"
        case 3:          return "cloud.fill"
        case 45, 48:     return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 61:         return "cloud.rain.fill"
        case 63:         return "cloud.rain.fill"
        case 65:         return "cloud.heavyrain.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77:         return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.rain.fill"
        case 85, 86:     return "cloud.snow.fill"
        case 95:         return "cloud.bolt.fill"
        case 96, 99:     return "cloud.bolt.rain.fill"
        default:         return "cloud.fill"
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
