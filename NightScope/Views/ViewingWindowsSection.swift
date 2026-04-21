import SwiftUI

struct ViewingWindowsSection: View {
    let summary: NightSummary

    private let viewModel = ViewingWindowsSectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if summary.viewingWindows.isEmpty {
                ViewingWindowsEmptyStateCardContent()
                    .glassCard()
                    .accessibilityElement(children: .contain)
            } else {
                ForEach(summary.viewingWindows, id: \.start) { window in
                    ViewingWindowCard(window: window, timeZone: summary.timeZone, viewModel: viewModel)
                }
            }
        }
    }
}

private struct ViewingWindowCard: View {
    let window: ViewingWindow
    let timeZone: TimeZone
    let viewModel: ViewingWindowsSectionViewModel

    var body: some View {
        ViewingWindowCardContent(window: window, timeZone: timeZone, viewModel: viewModel)
            .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.accessibilityDescription(for: window, timeZone: timeZone))
    }
}

struct MilkyWaySummaryCard: View {
    let summary: NightSummary

    private let viewModel = ViewingWindowsSectionViewModel()
    private var bestWindow: ViewingWindow? { summary.bestViewingWindow }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CardHeader(icon: AppIcons.Astronomy.sparkles, iconColor: .indigo, title: "天の川")
            if let window = bestWindow {
                ViewingWindowCardContent(window: window, timeZone: summary.timeZone, viewModel: viewModel)
            } else {
                ViewingWindowsEmptyStateCardContent()
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            bestWindow.map { viewModel.accessibilityDescription(for: $0, timeZone: summary.timeZone) }
                ?? L10n.tr("観測に適した時間帯がありません")
        )
    }
}

struct ViewingWindowCardContent: View {
    let window: ViewingWindow
    let timeZone: TimeZone
    let viewModel: ViewingWindowsSectionViewModel

    var body: some View {
        let timeAndPeakText = viewModel.timeAndPeakText(window, timeZone: timeZone)
        let altitudeText = viewModel.altitudeText(window)
        let directionText = viewModel.directionText(window)

        HStack(alignment: .center, spacing: Spacing.sm) {
            DirectionIndicator(azimuth: window.peakAzimuth)
                .frame(width: CardVisual.width, height: CardVisual.compassSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs / 2) {
                Text(timeAndPeakText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .panelTooltip(timeAndPeakText)
                Text(altitudeText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .panelTooltip(altitudeText)
                Text(directionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .panelTooltip(directionText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ViewingWindowsEmptyStateCardContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CardHeader(icon: AppIcons.Astronomy.sparkles, iconColor: .indigo, title: "天の川")
            ContentUnavailableView(
                L10n.tr("観測に適した時間帯がありません"),
                systemImage: AppIcons.Status.warning,
                description: Text(L10n.tr("銀河系中心が地平線上にある時間帯と天文薄明が重なりませんでした"))
            )
        }
    }
}

// MARK: - Direction Indicator (Compass)

private struct DirectionIndicator: View {
    let azimuth: Double

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2
            let tickLen: Double = 4

            // Outer ring
            var ring = Path()
            ring.addEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            ctx.stroke(ring,
                       with: .color(Color.white.opacity(CardVisual.trackOpacity)),
                       style: StrokeStyle(lineWidth: 1.5))

            // Cardinal tick marks (N/E/S/W)
            for deg in stride(from: 0.0, to: 360.0, by: 90.0) {
                let angle = Angle.degrees(deg - 90)
                let outerPt = CGPoint(
                    x: center.x + radius * cos(angle.radians),
                    y: center.y + radius * sin(angle.radians)
                )
                let innerPt = CGPoint(
                    x: center.x + (radius - tickLen) * cos(angle.radians),
                    y: center.y + (radius - tickLen) * sin(angle.radians)
                )
                var tick = Path()
                tick.move(to: outerPt)
                tick.addLine(to: innerPt)
                let isNorth = deg == 0
                ctx.stroke(tick,
                           with: .color(Color.white.opacity(isNorth ? 0.6 : 0.3)),
                           style: StrokeStyle(lineWidth: isNorth ? 2 : 1, lineCap: .round))
            }

            // Direction arrow
            let arrowAngle = Angle.degrees(azimuth - 90)
            let arrowLen = radius * 0.65
            let arrowEnd = CGPoint(
                x: center.x + arrowLen * cos(arrowAngle.radians),
                y: center.y + arrowLen * sin(arrowAngle.radians)
            )
            var arrow = Path()
            arrow.move(to: center)
            arrow.addLine(to: arrowEnd)
            ctx.stroke(arrow,
                       with: .color(Color.indigo.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Arrowhead
            let headSize: Double = 5
            let headAngle1 = Angle.degrees(azimuth - 90 + 150)
            let headAngle2 = Angle.degrees(azimuth - 90 - 150)
            let head1 = CGPoint(
                x: arrowEnd.x + headSize * cos(headAngle1.radians),
                y: arrowEnd.y + headSize * sin(headAngle1.radians)
            )
            let head2 = CGPoint(
                x: arrowEnd.x + headSize * cos(headAngle2.radians),
                y: arrowEnd.y + headSize * sin(headAngle2.radians)
            )
            var headPath = Path()
            headPath.move(to: head1)
            headPath.addLine(to: arrowEnd)
            headPath.addLine(to: head2)
            ctx.stroke(headPath,
                       with: .color(Color.indigo.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Center dot
            var dot = Path()
            dot.addEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
            ctx.fill(dot, with: .color(Color.white.opacity(0.5)))
        }
    }
}
