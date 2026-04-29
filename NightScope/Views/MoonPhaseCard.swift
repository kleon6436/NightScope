import SwiftUI

/// 月相と月齢から観測への影響を示すカード。
struct MoonPhaseCard: View {
    let summary: NightSummary

    private var moonAgeDays: Double {
        summary.moonPhaseAtMidnight * 29.53
    }

    var body: some View {
        let moonRecommendationText = summary.isMoonFavorable ? L10n.tr("撮影に適しています") : L10n.tr("月明かりに注意")

        VStack(alignment: .leading, spacing: Spacing.xs) {
            CardHeader(icon: summary.moonPhaseIcon, iconColor: .indigo, title: "月の状態")
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: summary.moonPhaseIcon)
                    .font(.system(size: CardVisual.moonIconSize))
                    .foregroundStyle(.indigo)
                    .summaryCardMetricVisualFrame()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(summary.moonPhaseName)
                        .font(.headline)
                        .lineLimit(1)
                        .panelTooltip(summary.moonPhaseName)
                    HStack(spacing: Spacing.xs) {
                        Text("月齢")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text(L10n.format("%.1f日", moonAgeDays))
                            .font(.body.monospacedDigit())
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(moonRecommendationText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .panelTooltip(moonRecommendationText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: CardVisual.metricVisualHeight, alignment: .leading)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "月の状態: %@、月齢%.1f日。%@",
                summary.moonPhaseName,
                moonAgeDays,
                moonRecommendationText
            )
        )
    }
}
