import SwiftUI

struct UpcomingNightsGrid: View {
    @ObservedObject var appController: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今後2週間の予報")
                    .font(.title3.bold())
                Spacer()
                if !Calendar.current.isDateInToday(appController.selectedDate) {
                    Button("今日") { appController.selectedDate = Date() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            let displayNights = appController.upcomingNights.filter { !$0.viewingWindows.isEmpty }

            if displayNights.isEmpty {
                Text("今後2週間は観測に適した夜がありません")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                GlassEffectContainer {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                        ForEach(displayNights, id: \.date) { night in
                            upcomingNightCard(night: night)
                        }
                    }
                }
            }
        }
    }

    private func upcomingNightCard(night: NightSummary) -> some View {
        let weather = appController.weatherService.summary(for: night.date)
        let isSelected = Calendar.current.isDate(night.date, inSameDayAs: appController.selectedDate)
        let index = appController.upcomingIndexes[Calendar.current.startOfDay(for: night.date)]

        return VStack(alignment: .leading, spacing: 6) {
            // ── ヘッダー ──
            HStack {
                Text(night.date, style: .date)
                    .font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 13))
                    Text(weather.map { String(format: "%.0f%%", $0.avgCloudCover) } ?? "—")
                        .font(.system(size: 13))
                }
                .foregroundColor(Color.cyan.opacity(0.9))
            }

            if let w = weather {
                HStack(spacing: 4) {
                    Image(systemName: w.weatherIconName)
                        .foregroundColor(weatherIconColor(code: w.representativeWeatherCode))
                        .font(.body)
                    Text(w.weatherLabel == w.cloudLabel
                         ? w.weatherLabel
                         : "\(w.weatherLabel)（\(w.cloudLabel)）")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: night.moonPhaseIcon)
                    .foregroundColor(Color(NSColor.systemIndigo))
                    .font(.body)
                Text(night.moonPhaseName)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Divider()

            // ── 星空 / 天の川 2カラム ──
            HStack(alignment: .top, spacing: 8) {
                // 左: 星空
                VStack(alignment: .leading, spacing: 3) {
                    Text("星空")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let darkRangeText: String = {
                        if let s = night.eveningDarkStart, let e = night.morningDarkEnd {
                            return "\(timeString(s))〜\(timeString(e))"
                        } else if let s = night.eveningDarkStart {
                            return "\(timeString(s))〜翌朝"
                        } else if let e = night.morningDarkEnd {
                            return "深夜〜\(timeString(e))"
                        } else {
                            return "—"
                        }
                    }()
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 5, verticalSpacing: 3) {
                        GridRow {
                            Image(systemName: "sparkles")
                                .frame(width: 14, alignment: .center)
                                .foregroundColor(index.map { scoreColor(for: $0.tier) } ?? .secondary)
                            if let idx = index {
                                Text("\(idx.label)")
                                    .font(.headline)
                                    .foregroundColor(scoreColor(for: idx.tier))
                                    .lineLimit(1)
                            } else {
                                Text("計算中…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        GridRow {
                            Image(systemName: "moon.stars")
                                .frame(width: 14, alignment: .center)
                            Text(darkRangeText)
                                .font(.body)
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                // 右: 天の川
                VStack(alignment: .leading, spacing: 3) {
                    Text("天の川")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 5, verticalSpacing: 3) {
                        GridRow {
                            Image(systemName: "star")
                                .frame(width: 14, alignment: .center)
                            Text(night.bestViewingTime.map { "見頃 \(timeString($0))" } ?? "見頃 —")
                                .font(.body)
                                .lineLimit(1)
                        }
                        GridRow {
                            Image(systemName: "clock")
                                .frame(width: 14, alignment: .center)
                            Text(String(format: "観測 %.1f時間", night.totalViewingHours))
                                .font(.body)
                                .lineLimit(1)
                        }
                        if let dir = night.bestDirection {
                            GridRow {
                                Image(systemName: "location.north.fill")
                                    .frame(width: 14, alignment: .center)
                                Text(dir)
                                    .font(.body)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 160)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appController.selectedDate = night.date
        }
    }

    private func scoreColor(for tier: StarGazingIndex.Tier) -> Color {
        switch tier {
        case .excellent, .good: return .green
        case .fair:             return .yellow
        case .poor:             return .orange
        case .bad:              return .red
        }
    }

    private func weatherIconColor(code: Int) -> Color {
        switch code {
        case 0, 1:       return .yellow
        case 2:          return .secondary
        case 3:          return .secondary
        case 45, 48:     return .secondary
        case 51...65:    return .blue
        case 71...77:    return Color.blue.opacity(0.7)
        case 80...82:    return .blue
        case 85, 86:     return Color.blue.opacity(0.7)
        case 95...99:    return .orange
        default:         return .secondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
