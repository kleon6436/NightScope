import SwiftUI

struct DarkTimeCardViewModel {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    var displayText: String {
        if let w = weather, let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return text.isEmpty ? "天候不良" : text
        }
        return summary.darkRangeText.isEmpty ? "暗い時間なし" : summary.darkRangeText
    }

    var isUnavailable: Bool {
        if let w = weather, let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return !text.contains("〜")
        }
        return summary.darkRangeText.isEmpty
    }

    var accessibilityLabel: String {
        "観測可能時間: \(displayText)"
    }
}
