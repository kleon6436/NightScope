import SwiftUI

struct DarkTimeCard: View {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    private var displayText: String {
        if let w = weather, let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return text.isEmpty ? "天候不良" : text
        }
        return summary.darkRangeText.isEmpty ? "暗い時間なし" : summary.darkRangeText
    }

    private var isUnavailable: Bool {
        if let w = weather, let text = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
            return !text.contains("〜")  // 時間帯文字列以外（天候不良・月明かり・空文字）はすべて不可
        }
        return summary.darkRangeText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Observation.clock)
                    .foregroundStyle(.green)
                    .font(.body)
                    .accessibilityHidden(true)
                Text("観測可能時間")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Text(displayText)
                .font(.headline)
                .foregroundStyle(isUnavailable ? .secondary : .primary)
            if !isUnavailable {
                Text(String(format: "暗い時間 %.1f時間", summary.totalDarkHours))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("観測可能時間: \(displayText)")
    }
}
