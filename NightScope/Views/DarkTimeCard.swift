import SwiftUI

struct DarkTimeCard: View {
    let summary: NightSummary

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
            if summary.darkRangeText.isEmpty {
                Text("暗い時間なし")
                    .font(.headline)
            } else {
                Text(summary.darkRangeText)
                    .font(.headline)
                Text(String(format: "暗い時間 %.1f時間", summary.totalDarkHours))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.darkRangeText.isEmpty
            ? "観測可能時間: 暗い時間なし"
            : "観測可能時間: \(summary.darkRangeText)、暗い時間\(String(format: "%.1f", summary.totalDarkHours))時間")
    }
}
