import SwiftUI

struct StarGazingIndexCard: View {
    let index: StarGazingIndex
    @ObservedObject var lightPollutionService: LightPollutionService

    var body: some View {
        let color = scoreColor(for: index.tier)
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("星空指数")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(index.score)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                        Text("/ 100")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .frame(height: 50)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { i in
                                Image(systemName: i < index.starCount ? "star.fill" : "star")
                                    .foregroundStyle(i < index.starCount ? color : Color.gray.opacity(0.4))
                                    .font(.body)
                            }
                        }
                        Text(index.label)
                            .font(.headline)
                            .foregroundStyle(color)
                    }

                    subScoreRow(label: "星空", score: index.constellationScore, maxScore: 50, color: Color(NSColor.systemIndigo))

                    if index.hasWeatherData {
                        subScoreRow(label: "気象", score: index.weatherScore, maxScore: 40, color: .cyan)
                    } else {
                        HStack(spacing: 6) {
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
                        subScoreRow(label: "光害", score: index.lightPollutionScore, maxScore: 10, color: .orange)
                    } else {
                        HStack(spacing: 6) {
                            Text("光害")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            if lightPollutionService.isLoading {
                                ProgressView()
                                    .controlSize(.mini)
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

                    subScoreRow(label: "天の川", score: index.milkyWayScore, maxScore: 25, color: .yellow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreColor(for tier: StarGazingIndex.Tier) -> Color {
        switch tier {
        case .excellent, .good: return .green
        case .fair:             return .yellow
        case .poor:             return .orange
        case .bad:              return .red
        }
    }

    private func subScoreRow(label: String, score: Int, maxScore: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            ProgressView(value: Double(score), total: Double(maxScore))
                .progressViewStyle(.linear)
                .tint(color)
                .frame(width: 100)
            Text("\(score)/\(maxScore)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
