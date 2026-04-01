import SwiftUI

struct StarGazingIndexCard: View {
    let index: StarGazingIndex
    @ObservedObject var lightPollutionService: LightPollutionService
    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = index.tier.color
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
                .accessibilityHidden(true)

            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("星空指数")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs / 2) {
                        Text("\(index.score)")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(color)
                            .accessibilityLabel("星空指数 \(index.score)点")
                        Text("/ 100")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                Divider()
                    .frame(height: 50)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs / 4) {
                            ForEach(0..<5) { i in
                                Image(systemName: i < index.starCount ? AppIcons.Astronomy.starFill : AppIcons.Astronomy.star)
                                    .foregroundStyle(i < index.starCount ? color : Color.secondary.opacity(0.4))
                                    .font(.body)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("評価: 星\(index.starCount)つ（5段階）")
                        Text(index.label)
                            .font(.headline)
                            .foregroundStyle(color)
                        Spacer()
                        Image(systemName: AppIcons.Controls.chevronDown)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(reduceMotion ? .none : .standard, value: isExpanded)
                            .accessibilityHidden(true)
                    }

                    if isExpanded {
                        Group {
                            subScoreRow(label: "星空", score: index.constellationScore, maxScore: StarGazingIndex.maxConstellationScore, color: Color.indigo)

                            if index.hasWeatherData {
                                subScoreRow(label: "気象", score: index.weatherScore, maxScore: StarGazingIndex.maxWeatherScore, color: .cyan)
                            } else {
                                HStack(spacing: Spacing.xs) {
                                    Text("気象")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .leading)
                                    Text("データなし")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if index.hasLightPollutionData {
                                subScoreRow(label: "光害", score: index.lightPollutionScore, maxScore: StarGazingIndex.maxLightPollutionScore, color: .orange)
                            } else {
                                HStack(spacing: Spacing.xs) {
                                    Text("光害")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .leading)
                                    if lightPollutionService.isLoading {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .accessibilityLabel("光害データを取得中")
                                    } else if lightPollutionService.fetchFailed {
                                        Text("取得失敗")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("取得中...")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Layout.cardPadding)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .onTapGesture {
            withAnimation(reduceMotion ? .none : .standard) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("詳細スコア")
        .accessibilityValue(isExpanded ? "展開中" : "折り畳み中")
        .accessibilityHint(isExpanded ? "タップして折り畳む" : "タップして詳細を表示")
    }

    private func subScoreRow(label: String, score: Int, maxScore: Int, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            ProgressView(value: Double(score), total: Double(maxScore))
                .progressViewStyle(.linear)
                .tint(color)
                .frame(width: 100)
                .accessibilityLabel("\(label)")
                .accessibilityValue("\(score)/\(maxScore)")
            Text("\(score)/\(maxScore)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
