import SwiftUI

struct NightWeatherCard: View {
    let weather: DayWeatherSummary?
    @ObservedObject var viewModel: NightWeatherCardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Weather.cloud)
                    .foregroundStyle(.cyan)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text("天気 (夜間)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let w = weather {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    CloudCoverArc(cloudCover: w.avgCloudCover)
                        .frame(width: 52, height: 28)
                        .accessibilityLabel("雲量 \(Int(w.avgCloudCover))%")

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(viewModel.weatherLabel(w))
                            .font(.headline)
                        Text(viewModel.formatPrecipitation(w.maxPrecipitation))
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text(viewModel.formatWindSpeed(w.avgWindSpeed))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("データなし")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("10日以内のみ")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityDescription(weather: weather, isLoading: false))
    }
}

// MARK: - Cloud Cover Arc Gauge

private struct CloudCoverArc: View {
    let cloudCover: Double  // 0〜100

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h
            let r  = min(w, h * 2) * 0.44
            let lineW: Double = 5

            // Track arc (180° semicircle, left→right)
            var trackPath = Path()
            trackPath.addArc(center: CGPoint(x: cx, y: cy),
                             radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(0),
                             clockwise: false)
            ctx.stroke(trackPath,
                       with: .color(Color.white.opacity(0.12)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            // Filled arc
            let fillDeg = 180.0 * min(max(cloudCover / 100.0, 0), 1)
            var fillPath = Path()
            fillPath.addArc(center: CGPoint(x: cx, y: cy),
                            radius: r,
                            startAngle: .degrees(180),
                            endAngle: .degrees(180 + fillDeg),
                            clockwise: false)
            let arcColor = cloudCover < 30 ? Color.cyan
                         : cloudCover < 70 ? Color.blue
                         : Color.gray
            ctx.stroke(fillPath,
                       with: .color(arcColor.opacity(0.85)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            // Percentage label
            ctx.draw(
                Text(String(format: "%.0f%%", cloudCover))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: cx, y: cy - r * 0.35))
        }
    }
}

