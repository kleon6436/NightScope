import SwiftUI

struct DarkTimeCardViewModel {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    private var hasReliableWeatherCoverage: Bool {
        guard let weather else { return false }
        return summary.hasReliableWeatherData(nighttimeHours: weather.nighttimeHours)
    }

    var displayText: String {
        if let w = weather,
           hasReliableWeatherCoverage,
           let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return text.isEmpty ? L10n.tr("天候不良") : text
        }
        return summary.darkRangeText.isEmpty ? L10n.tr("暗い時間なし") : summary.darkRangeText
    }

    var isUnavailable: Bool {
        if let w = weather, let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return !text.contains("〜")
        }
        return summary.darkRangeText.isEmpty
    }

    var accessibilityLabel: String {
        L10n.format("観測可能時間: %@", displayText)
    }

    var supportingText: String {
        if weather == nil {
            return L10n.tr("天文学的な暗夜時間")
        }
        return hasReliableWeatherCoverage
            ? L10n.tr("天候・月明かりを考慮")
            : L10n.tr("天気データ不足のため暗夜時間を表示")
    }
}
