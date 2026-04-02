import SwiftUI

struct UpcomingNightsGrid: View {
    @ObservedObject var viewModel: UpcomingNightsGridViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("今後2週間の予報")
                    .font(.title3.bold())
                Spacer()
                if !Calendar.current.isDateInToday(viewModel.selectedDate) {
                    Button("今日") { viewModel.setSelectedDate(Date()) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("今日の日付に移動")
                }
            }

            let displayNights = viewModel.displayNights

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
        let weather = viewModel.weatherSummary(for: night.date)
        let isSelected = Calendar.current.isDate(night.date, inSameDayAs: viewModel.selectedDate)
        let index = viewModel.starGazingIndex(for: night.date)

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            cardHeader(night: night, weather: weather)
            if let weather {
                weatherDetailRow(weather: weather)
            }
            moonPhaseRow(night: night)

            Divider()

            observationColumns(night: night, weather: weather, index: index)
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
            viewModel.setSelectedDate(night.date)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.cardAccessibilityLabel(night: night, weather: weather, index: index))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cardHeader(night: NightSummary, weather: DayWeatherSummary?) -> some View {
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
    }

    private func weatherDetailRow(weather: DayWeatherSummary) -> some View {
        HStack(spacing: Spacing.xs / 2) {
            Image(systemName: weather.weatherIconName)
                .foregroundStyle(viewModel.weatherIconColor(code: weather.representativeWeatherCode))
                .font(.body)
                .accessibilityHidden(true)
            Text(weather.weatherLabel == weather.cloudLabel
                 ? weather.weatherLabel
                 : "\(weather.weatherLabel)（\(weather.cloudLabel)）")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func moonPhaseRow(night: NightSummary) -> some View {
        HStack(spacing: Spacing.xs / 2) {
            Image(systemName: night.moonPhaseIcon)
                .foregroundStyle(Color.indigo)
                .font(.body)
                .accessibilityHidden(true)
            Text(night.moonPhaseName)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func observationColumns(
        night: NightSummary,
        weather: DayWeatherSummary?,
        index: StarGazingIndex?
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            starGazingColumn(night: night, weather: weather, index: index)
            Divider()
            milkyWayColumn(night: night)
        }
        .frame(maxHeight: .infinity)
    }

    private func starGazingColumn(
        night: NightSummary,
        weather: DayWeatherSummary?,
        index: StarGazingIndex?
    ) -> some View {
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
                    if let index {
                        Text(index.label)
                            .font(.headline)
                            .foregroundStyle(index.tier.color)
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
                    Text(viewModel.observableRangeText(night: night, weather: weather))
                        .font(.body)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func milkyWayColumn(night: NightSummary) -> some View {
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
                if let direction = night.bestDirection {
                    GridRow {
                        Image(systemName: AppIcons.Observation.azimuthArrow)
                            .frame(width: Layout.gridIconWidth, alignment: .center)
                            .accessibilityHidden(true)
                        Text(direction)
                            .font(.body)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
