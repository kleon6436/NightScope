import SwiftUI

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
                    .frame(width: CardVisual.width)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs / 2) {
                    Text(summary.moonPhaseName)
                        .font(.headline)
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
