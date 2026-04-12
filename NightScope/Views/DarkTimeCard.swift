import SwiftUI

struct DarkTimeCard: View {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    private var viewModel: DarkTimeCardViewModel {
        DarkTimeCardViewModel(summary: summary, weather: weather)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CardHeader(icon: AppIcons.Observation.clock, iconColor: .green, title: "観測可能時間")
            HStack(alignment: .center, spacing: Spacing.sm) {
                DarkTimeArc(darkHours: summary.totalDarkHours)
                    .frame(width: CardVisual.width, height: CardVisual.arcHeight)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(viewModel.displayText)
                        .font(.headline)
                        .foregroundStyle(viewModel.isUnavailable ? .secondary : .primary)
                        .lineLimit(1)
                    if !viewModel.isUnavailable {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs / 2) {
                            Text("暗い時間")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f時間", summary.totalDarkHours))
                                .font(.body.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.supportingText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityLabel)
    }
}

// MARK: - Dark Time Arc Gauge

private struct DarkTimeArc: View {
    let darkHours: Double

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height
            let r = min(size.width, size.height * 2) * 0.44
            let lineW = CardVisual.strokeWidth

            var track = Path()
            track.addArc(center: CGPoint(x: cx, y: cy),
                         radius: r, startAngle: .degrees(180), endAngle: .degrees(0),
                         clockwise: false)
            ctx.stroke(track,
                       with: .color(Color.white.opacity(CardVisual.trackOpacity)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            let fraction = min(max(darkHours / 12.0, 0), 1)
            let deg = 180.0 * fraction
            var prog = Path()
            prog.addArc(center: CGPoint(x: cx, y: cy),
                        radius: r, startAngle: .degrees(180),
                        endAngle: .degrees(180 + deg), clockwise: false)
            let color: Color = darkHours >= 8 ? .green : darkHours >= 5 ? .teal : .orange
            ctx.stroke(prog,
                       with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            ctx.draw(
                Text(String(format: "%.1fh", darkHours))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: cx, y: cy - r * 0.35)
            )
        }
    }
}
