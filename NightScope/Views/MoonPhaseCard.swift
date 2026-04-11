import SwiftUI

struct MoonPhaseCard: View {
    let summary: NightSummary

    private var moonAgeDays: Double {
        summary.moonPhaseAtMidnight * 29.53
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: summary.moonPhaseIcon)
                    .foregroundStyle(Color.indigo)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text("月の状態")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Text(summary.moonPhaseName)
                .font(.headline)
            HStack(spacing: Spacing.xs) {
                Text("月齢")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f日", moonAgeDays))
                    .font(.body.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("月の状態: \(summary.moonPhaseName)、月齢\(String(format: "%.1f", moonAgeDays))日。\(summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意")")
    }
}
