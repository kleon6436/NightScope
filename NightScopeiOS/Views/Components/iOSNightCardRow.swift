import SwiftUI

struct iOSNightCardRow: View {
    let night: NightSummary
    let index: StarGazingIndex?
    let weather: DayWeatherSummary?
    let rangeText: String
    let isReliableWeather: Bool
    let hasPartialWeather: Bool
    let isForecastOutOfRange: Bool
    let isSelected: Bool

    private var presentation: ForecastCardPresentation {
        ForecastCardPresentation(
            night: night,
            weather: weather,
            timeZone: night.timeZone,
            isReliableWeather: isReliableWeather,
            hasPartialWeather: hasPartialWeather,
            isForecastOutOfRange: isForecastOutOfRange
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(presentation.shortDateLabel)
                    .font(.headline)
                if let label = presentation.relativeNightLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, IOSDesignTokens.NightRow.relativeLabelHorizontalPadding)
                        .padding(.vertical, IOSDesignTokens.NightRow.relativeLabelVerticalPadding)
                        .background(.tertiary, in: Capsule())
                }
                Spacer()
                if let index {
                    HStack(spacing: IOSDesignTokens.NightRow.starSpacing) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < index.starCount ? AppIcons.Astronomy.starFill : AppIcons.Astronomy.star)
                                .foregroundStyle(
                                    i < index.starCount
                                    ? index.tier.color
                                    : Color.secondary.opacity(IOSDesignTokens.NightRow.inactiveStarOpacity)
                                )
                                .font(.caption)
                        }
                    }
                    Text(index.label)
                        .font(.caption.bold())
                        .foregroundStyle(index.tier.color)
                }
            }

            HStack(spacing: Spacing.sm) {
                Label(night.moonPhaseName, systemImage: night.moonPhaseIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isReliableWeather {
                    Label(presentation.cloudCoverText, systemImage: AppIcons.Weather.cloud)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let detailText = presentation.weatherDetailText {
                    Label(detailText, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(rangeText, systemImage: AppIcons.Observation.clock)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: IOSDesignTokens.NightRow.selectionBorderWidth)
        )
    }
}
