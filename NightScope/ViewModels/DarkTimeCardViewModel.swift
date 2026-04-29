import SwiftUI

/// 暗夜時間帯カードの表示文言を組み立てる ViewModel。
///
/// `NightSummary` と天気データを突き合わせて、UI 用の短いラベルと補助文を返す。
struct DarkTimeCardViewModel {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    /// 天候データが十分に信頼できるかどうかを表す。
    private var hasReliableWeatherCoverage: Bool {
        guard let weather else { return false }
        return summary.hasUsableWeatherData(nighttimeHours: weather.nighttimeHours)
    }

    /// カード本文に表示する文言。
    var displayText: String {
        if let weatherText = weatherAwareText() {
            return weatherText
        }
        return summary.darkRangeText.isEmpty ? L10n.tr("暗い時間なし") : summary.darkRangeText
    }

    /// 天候を考慮した表示文言を優先して返す。
    private func weatherAwareText() -> String? {
        guard let w = weather,
              hasReliableWeatherCoverage,
              let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) else {
            return nil
        }
        return text.isEmpty ? L10n.tr("天候不良") : text
    }

    /// 現在の条件でカードを「利用不可」とみなすかを返す。
    var isUnavailable: Bool {
        if let w = weather, let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return !text.contains("〜")
        }
        return summary.darkRangeText.isEmpty
    }

    /// VoiceOver 向けに、カードの要点を読み上げやすい形で返す。
    var accessibilityLabel: String {
        L10n.format("観測可能時間: %@", displayText)
    }

    /// 天候の有無に応じて補助説明を切り替える。
    var supportingText: String {
        if weather == nil {
            return L10n.tr("天文学的な暗夜時間")
        }
        return hasReliableWeatherCoverage
            ? L10n.tr("天候・月明かりを考慮")
            : L10n.tr("天気データ不足のため暗夜時間を表示")
    }
}
