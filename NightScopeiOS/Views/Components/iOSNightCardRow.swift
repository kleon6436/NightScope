import SwiftUI

struct iOSNightCardRow: View {
    let night: NightSummary
    let index: StarGazingIndex?
    let weather: DayWeatherSummary?
    let rangeText: String
    let isReliableWeather: Bool
    let hasPartialWeather: Bool
    let isForecastOutOfRange: Bool
    let hasWeatherLoadError: Bool
    let isSelected: Bool

    private var presentation: ForecastCardPresentation {
        ForecastCardPresentation(
            night: night,
            weather: weather,
            timeZone: night.timeZone,
            isReliableWeather: isReliableWeather,
            hasPartialWeather: hasPartialWeather,
            isForecastOutOfRange: isForecastOutOfRange,
            hasWeatherLoadError: hasWeatherLoadError
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IOSDesignTokens.NightRow.contentSpacing) {
            headerRow
            metadataSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, IOSDesignTokens.NightRow.cardHorizontalPadding)
        .padding(.vertical, IOSDesignTokens.NightRow.cardVerticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: IOSDesignTokens.NightRow.cardMinHeight,
            alignment: .center
        )
        .glassEffectCompat(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: IOSDesignTokens.NightRow.selectionBorderWidth)
        )
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(presentation.shortDateLabel)
                .font(.headline.monospacedDigit())
                .fontWeight(.semibold)
            if let label = presentation.relativeNightLabel {
                Text(label)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, IOSDesignTokens.NightRow.relativeLabelHorizontalPadding)
                    .padding(.vertical, IOSDesignTokens.NightRow.relativeLabelVerticalPadding)
                    .background(.tertiary, in: Capsule())
            }
            Spacer(minLength: Spacing.xs)
            if let index {
                HStack(spacing: IOSDesignTokens.NightRow.starSpacing) {
                    ForEach(0..<5) { i in
                        Image(systemName: i < index.starCount ? AppIcons.Astronomy.starFill : AppIcons.Astronomy.star)
                            .foregroundStyle(
                                i < index.starCount
                                ? index.tier.color
                                : Color.secondary.opacity(IOSDesignTokens.NightRow.inactiveStarOpacity)
                            )
                            .font(.footnote)
                    }
                }
                Text(index.label)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(index.tier.color)
            }
        }
    }

    private var metadataSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: IOSDesignTokens.NightRow.metadataGroupSpacing) {
            moonMetadataItem
            weatherMetadataItem
            rangeMetadataItem
            Spacer(minLength: 0)
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
                .font(.footnote)
                .foregroundStyle(iconTint)
                .frame(width: IOSDesignTokens.NightRow.metadataIconWidth, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(IOSDesignTokens.NightRow.metadataMinimumScaleFactor)
                .allowsTightening(true)
        }
    }
}
