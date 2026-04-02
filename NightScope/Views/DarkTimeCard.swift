import SwiftUI

struct DarkTimeCard: View {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    private var viewModel: DarkTimeCardViewModel {
        DarkTimeCardViewModel(summary: summary, weather: weather)
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
            Text(viewModel.displayText)
                .font(.headline)
                .foregroundStyle(viewModel.isUnavailable ? .secondary : .primary)
            if !viewModel.isUnavailable {
                Text(String(format: "暗い時間 %.1f時間", summary.totalDarkHours))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityLabel)
    }
}
