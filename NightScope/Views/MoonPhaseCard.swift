import SwiftUI

struct MoonPhaseCard: View {
    let summary: NightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: summary.moonPhaseIcon)
                    .foregroundStyle(Color(NSColor.systemIndigo))
                    .font(.body)
                    .accessibilityHidden(true)
                Text("月の状態")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Text(summary.moonPhaseName)
                .font(.headline)
            Text(summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("月の状態: \(summary.moonPhaseName)。\(summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意")")
    }
}
