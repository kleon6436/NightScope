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
            headerRow
            metadataSection
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: IOSDesignTokens.NightRow.selectionBorderWidth)
        )
    }

    private var headerRow: some View {
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
    }

    private var metadataSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: IOSDesignTokens.NightRow.metadataGroupSpacing) {
                moonMetadataItem
                weatherMetadataItem
                rangeMetadataItem
            }
            VStack(alignment: .leading, spacing: IOSDesignTokens.NightRow.metadataLineSpacing) {
                HStack(spacing: IOSDesignTokens.NightRow.metadataGroupSpacing) {
                    moonMetadataItem
                    weatherMetadataItem
                }
                rangeMetadataItem
            }
        }
    }

    private var moonMetadataItem: some View {
        metadataItem(
            text: night.moonPhaseName,
            systemImage: night.moonPhaseIcon
        )
    }

    @ViewBuilder
    private var weatherMetadataItem: some View {
        if isReliableWeather, let weather, let detailText = presentation.weatherDetailText {
            metadataItem(
                text: detailText,
                systemImage: weather.weatherIconName,
                iconTint: WeatherPresentation.color(forWeatherCode: weather.representativeWeatherCode)
            )
        } else if let detailText = presentation.weatherDetailText {
            metadataItem(
                text: detailText,
                systemImage: "questionmark.circle"
            )
        }
    }

    private var rangeMetadataItem: some View {
        metadataItem(
            text: rangeText,
            systemImage: AppIcons.Observation.clock
        )
    }

    private func metadataItem(
        text: String,
        systemImage: String,
        iconTint: Color = .secondary
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IOSDesignTokens.NightRow.metadataIconSpacing) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(iconTint)
                .frame(width: IOSDesignTokens.NightRow.metadataIconWidth, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}
