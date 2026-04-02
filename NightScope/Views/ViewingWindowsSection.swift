import SwiftUI

struct ViewingWindowsSection: View {
    let summary: NightSummary

    private var viewModel: ViewingWindowsSectionViewModel {
        ViewingWindowsSectionViewModel(summary: summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("天の川 観測情報")
                .font(.title3.bold())

            if summary.viewingWindows.isEmpty {
                ContentUnavailableView(
                    "観測に適した時間帯がありません",
                    systemImage: AppIcons.Status.warning,
                    description: Text("銀河系中心が地平線上にある時間帯と天文薄明が重なりませんでした")
                )
            } else {
                ForEach(summary.viewingWindows, id: \.start) { window in
                    windowRow(window: window)
                }
            }
        }
    }

    private func windowRow(window: ViewingWindow) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(viewModel.windowTimeText(window))
                    .font(.title3.bold())

                HStack(spacing: Spacing.sm) {
                    Label(viewModel.durationText(window), systemImage: AppIcons.Observation.clock)
                    Label(viewModel.altitudeText(window), systemImage: AppIcons.Observation.altitudeArrow)
                    Label(viewModel.peakTimeText(window), systemImage: AppIcons.Astronomy.star)
                    Label(window.peakDirectionName, systemImage: AppIcons.Observation.azimuthArrow)
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Label(viewModel.moonStatusLabel(for: window), systemImage: summary.isMoonFavorable ? AppIcons.Status.checkmarkFill : AppIcons.Astronomy.moonFill)
                    .font(.body)
                    .foregroundStyle(summary.isMoonFavorable ? .green : .orange)
            }
        }
        .padding(Layout.cardPadding)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityDescription(for: window))
    }
}
