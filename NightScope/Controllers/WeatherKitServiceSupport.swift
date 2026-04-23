import Foundation
import WeatherKit
import CoreLocation

// MARK: - WeatherCondition → WMO code mapper

enum WeatherConditionMapper {
    /// WeatherKit の WeatherCondition を WMO 天気コードへ変換する。
    /// 対応表は DayWeatherSummary.weatherIconName / weatherLabel が使う WMO コード体系に準拠。
    /// 不明 case は曇り(3) へフォールバック。
    static func wmoCode(for condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot:
            return 0
        case .mostlyClear:
            return 1
        case .partlyCloudy, .smoky, .haze, .blowingDust:
            return 2
        case .mostlyCloudy, .cloudy:
            return 3
        case .foggy:
            return 45
        case .drizzle, .freezingDrizzle:
            return 51
        case .rain:
            return 61
        case .heavyRain:
            return 65
        case .sunShowers, .isolatedThunderstorms:
            return 80
        case .scatteredThunderstorms, .thunderstorms, .strongStorms:
            return 95
        case .hail:
            return 96
        case .blizzard, .wintryMix:
            return 71
        case .flurries, .snow, .sunFlurries, .blowingSnow:
            return 73
        case .heavySnow:
            return 75
        case .sleet, .freezingRain:
            return 68
        case .tropicalStorm, .hurricane:
            return 95
        // 現 WeatherKit SDK では晴れ系として扱う case
        case .breezy, .windy:
            return 2
        case .frigid:
            return 0
        @unknown default:
            return 3
        }
    }
}
