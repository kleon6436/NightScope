import SwiftUI

struct UpcomingNightsGrid: View {
    @ObservedObject var appController: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("今後2週間の予報")
                    .font(.title3.bold())
                Spacer()
                if !Calendar.current.isDateInToday(appController.selectedDate) {
                    Button("今日") { appController.selectedDate = Date() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("今日の日付に移動")
                }
            }

            let displayNights = appController.upcomingNights.filter { !$0.viewingWindows.isEmpty }

            if displayNights.isEmpty {
                ContentUnavailableView(
                    "観測に適した夜がありません",
                    systemImage: AppIcons.Astronomy.moonZzz,
                    description: Text("今後2週間は天の川の観測に適した夜がありませんでした")
                )
            } else {
                GlassEffectContainer {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Spacing.xs)], spacing: Spacing.xs) {
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

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            // ── ヘッダー ──
            HStack {
                Text(night.date, style: .date)
                    .font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: AppIcons.Weather.cloudFill)
                        .font(.body)
                        .accessibilityHidden(true)
                    Text(weather.map { String(format: "%.0f%%", $0.avgCloudCover) } ?? "—")
                        .font(.body)
                }
                .foregroundStyle(Color.cyan.opacity(0.9))
            }

            if let w = weather {
                HStack(spacing: Spacing.xs / 2) {
                    Image(systemName: w.weatherIconName)
                        .foregroundStyle(weatherIconColor(code: w.representativeWeatherCode))
                        .font(.body)
                        .accessibilityHidden(true)
                    Text(w.weatherLabel == w.cloudLabel
                         ? w.weatherLabel
                         : "\(w.weatherLabel)（\(w.cloudLabel)）")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: Spacing.xs / 2) {
                Image(systemName: night.moonPhaseIcon)
                    .foregroundStyle(Color.indigo)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(night.moonPhaseName)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // ── 星空 / 天の川 2カラム ──
            HStack(alignment: .top, spacing: Spacing.xs) {
                // 左: 星空
                VStack(alignment: .leading, spacing: 3) {
                    Text("星空")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.xs / 2, verticalSpacing: 3) {
                        GridRow {
                            Image(systemName: AppIcons.Astronomy.sparkles)
                                .frame(width: Layout.gridIconWidth, alignment: .center)
                                .foregroundStyle(index.map { $0.tier.color } ?? .secondary)
                                .accessibilityHidden(true)
                            if let idx = index {
                                Text("\(idx.label)")
                                    .font(.headline)
                                    .foregroundStyle(idx.tier.color)
                                    .lineLimit(1)
                            } else {
                                Text("計算中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        GridRow {
                            Image(systemName: AppIcons.Astronomy.moonStars)
                                .frame(width: Layout.gridIconWidth, alignment: .center)
                                .accessibilityHidden(true)
                            Text({
                                if let w = weather,
                                   let text = night.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
                                    return text.isEmpty ? "天候不良" : text
                                }
                                return night.darkRangeText.isEmpty ? "—" : night.darkRangeText
                            }())
                                .font(.body)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                // 右: 天の川
                VStack(alignment: .leading, spacing: 3) {
                    Text("天の川")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.xs / 2, verticalSpacing: 3) {
                        GridRow {
                            Image(systemName: AppIcons.Astronomy.star)
                                .frame(width: Layout.gridIconWidth, alignment: .center)
                                .accessibilityHidden(true)
                            Text(night.bestViewingTime.map { "見頃 \($0.nightTimeString())" } ?? "見頃 —")
                                .font(.body)
                                .lineLimit(1)
                        }
                        GridRow {
                            Image(systemName: AppIcons.Observation.clock)
                                .frame(width: Layout.gridIconWidth, alignment: .center)
                                .accessibilityHidden(true)
                            Text(String(format: "観測 %.1f時間", night.totalViewingHours))
                                .font(.body)
                                .lineLimit(1)
                        }
                        if let dir = night.bestDirection {
                            GridRow {
                                Image(systemName: AppIcons.Observation.azimuthArrow)
                                    .frame(width: Layout.gridIconWidth, alignment: .center)
                                    .accessibilityHidden(true)
                                Text(dir)
                                    .font(.body)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Layout.upcomingCardHeight)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appController.selectedDate = night.date
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel(night: night, weather: weather, index: index))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    private func cardAccessibilityLabel(night: NightSummary, weather: DayWeatherSummary?, index: StarGazingIndex?) -> String {
        var parts: [String] = []
        parts.append(Self.cardDateFormatter.string(from: night.date))
        if let idx = index { parts.append("星空指数\(idx.score)") }
        if let w = weather { parts.append("天気\(w.weatherLabel)") }
        parts.append("月: \(night.moonPhaseName)")
        return parts.joined(separator: "、")
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
}
