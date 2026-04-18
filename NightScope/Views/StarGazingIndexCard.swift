import SwiftUI

private enum StarGazingIndexCardMetrics {
    static let visualWidth: CGFloat = 60
    static let starSpacing: CGFloat = 4
}

struct StarGazingIndexCard: View {
    let index: StarGazingIndex
    @ObservedObject var lightPollutionViewModel: StarGazingIndexCardViewModel
    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = index.tier.color
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button(action: toggleExpanded) {
                HStack {
                    CardHeader(icon: AppIcons.Astronomy.starFill, iconColor: color, title: "星空指数")
                    Spacer()
                    Image(systemName: AppIcons.Controls.chevronDown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(reduceMotion ? .none : .standard, value: isExpanded)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.format("星空指数 %d点、%@。", index.score, index.label))
            .accessibilityValue(isExpanded ? L10n.tr("展開中") : L10n.tr("折り畳み中"))
            .accessibilityHint(isExpanded ? L10n.tr("ダブルタップで折り畳む") : L10n.tr("ダブルタップで詳細を表示"))

            HStack(alignment: .center, spacing: Spacing.md) {
                scoreVisual(color: color)
                    .frame(width: StarGazingIndexCardMetrics.visualWidth)
                    .accessibilityHidden(true)

                StarTierSummary(index: index, color: color)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isExpanded {
                expandedContent(color: color)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Shared Components

    private func scoreVisual(color: Color) -> some View {
        ScoreArc(score: index.score, color: color)
            .frame(width: StarGazingIndexCardMetrics.visualWidth, height: CardVisual.arcHeight)
    }

    @ViewBuilder
    private func expandedContent(color: Color) -> some View {
        subScoreRow(label: "星空", score: index.constellationScore, maxScore: StarGazingIndex.maxConstellationScore, color: Color.indigo)

        if index.hasWeatherData {
            subScoreRow(label: "気象", score: index.weatherScore, maxScore: StarGazingIndex.maxWeatherScore, color: .cyan)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                subScoreLabel("気象")
                Text("データなし")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }

        if index.hasLightPollutionData {
            subScoreRow(label: "光害", score: index.lightPollutionScore, maxScore: StarGazingIndex.maxLightPollutionScore, color: .orange)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                subScoreLabel("光害")
                if lightPollutionViewModel.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(L10n.tr("光害データを取得中"))
                } else if lightPollutionViewModel.fetchFailed {
                    Text(L10n.tr("取得失敗"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.tr("取得中..."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func subScoreRow(label: String, score: Int, maxScore: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            subScoreLabel(label)
            ProgressView(value: Double(score), total: Double(maxScore))
                .progressViewStyle(.linear)
                .tint(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(label)")
                .accessibilityValue("\(score)/\(maxScore)")
            Text("\(score)/\(maxScore)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func subScoreLabel(_ label: String) -> some View {
        Text(label)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func toggleExpanded() {
        withAnimation(reduceMotion ? .none : .standard) {
            isExpanded.toggle()
        }
    }
}

#if os(macOS)
struct MacStarGazingIndexCard: View {
    let index: StarGazingIndex
    @ObservedObject var lightPollutionViewModel: StarGazingIndexCardViewModel

    var body: some View {
        let color = index.tier.color
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CardHeader(icon: AppIcons.Astronomy.starFill, iconColor: color, title: "星空指数")

            HStack(alignment: .center, spacing: Spacing.md) {
                ScoreArc(score: index.score, color: color)
                    .frame(
                        width: StarGazingIndexCardMetrics.visualWidth,
                        height: CardVisual.arcHeight
                    )
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Spacing.sm) {
                        StarTierSummary(index: index, color: color)
                        inlineBreakdown
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        StarTierSummary(index: index, color: color)
                        inlineBreakdown
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var inlineBreakdown: some View {
        HStack(spacing: Spacing.xs) {
            inlineScore(label: "星空", value: "\(index.constellationScore)/\(StarGazingIndex.maxConstellationScore)")
            inlineScore(label: "気象", value: weatherValue)
            inlineScore(label: "光害", value: lightPollutionValue)
        }
        .font(.body)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .allowsTightening(true)
    }

    private var weatherValue: String {
        guard index.hasWeatherData else {
            return L10n.tr("データなし")
        }
        return "\(index.weatherScore)/\(StarGazingIndex.maxWeatherScore)"
    }

    private var lightPollutionValue: String {
        guard !index.hasLightPollutionData else {
            return "\(index.lightPollutionScore)/\(StarGazingIndex.maxLightPollutionScore)"
        }
        if lightPollutionViewModel.isLoading {
            return L10n.tr("取得中...")
        }
        if lightPollutionViewModel.fetchFailed {
            return L10n.tr("取得失敗")
        }
        return L10n.tr("取得中...")
    }

    private var accessibilityLabel: String {
        L10n.format("星空指数 %d点、%@。", index.score, index.label)
        + L10n.format("星空 %d/%d。", index.constellationScore, StarGazingIndex.maxConstellationScore)
        + L10n.format("気象 %@。", weatherValue)
        + L10n.format("光害 %@。", lightPollutionValue)
    }

    private func inlineScore(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
    }
}
#endif

// MARK: - Score Arc Canvas

private struct StarTierSummary: View {
    let index: StarGazingIndex
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: StarGazingIndexCardMetrics.starSpacing) {
                ForEach(0..<5) { i in
                    Image(systemName: i < index.starCount ? AppIcons.Astronomy.starFill : AppIcons.Astronomy.star)
                        .foregroundStyle(i < index.starCount ? color : Color.secondary.opacity(0.4))
                        .font(.subheadline)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("評価: 星%dつ（5段階）", index.starCount))

            Text(index.label)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xs / 2)
                .background(color.opacity(0.14), in: Capsule())
        }
    }
}

private struct ScoreArc: View {
    let score: Int
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height
            let r = min(size.width, size.height * 2) * 0.44
            let lineW: Double = 5

            // Track
            var track = Path()
            track.addArc(center: CGPoint(x: cx, y: cy),
                         radius: r, startAngle: .degrees(180), endAngle: .degrees(0),
                         clockwise: false)
            ctx.stroke(track,
                       with: .color(Color.white.opacity(0.12)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            // Progress
            let deg = 180.0 * Double(min(max(score, 0), 100)) / 100.0
            var prog = Path()
            prog.addArc(center: CGPoint(x: cx, y: cy),
                        radius: r, startAngle: .degrees(180),
                        endAngle: .degrees(180 + deg), clockwise: false)
            ctx.stroke(prog,
                       with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            ctx.draw(
                Text("\(score)/100")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85)),
                at: CGPoint(x: cx, y: cy - r * 0.35)
            )
        }
    }
}
