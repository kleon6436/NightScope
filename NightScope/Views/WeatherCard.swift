import SwiftUI

struct NightWeatherCard: View {
    let weather: DayWeatherSummary?
    @ObservedObject var viewModel: NightWeatherCardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CardHeader(icon: AppIcons.Weather.cloud, iconColor: .cyan, title: "天気 (夜間)")
            HStack(alignment: .center, spacing: Spacing.sm) {
                weatherVisual
                weatherTextContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityDescription(weather: weather, isLoading: false))
    }

    @ViewBuilder
    private var weatherVisual: some View {
        WeatherSymbolVisual(weather: weather)
            .frame(width: CardVisual.width, height: CardVisual.arcHeight)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var weatherTextContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let weather {
                Text(viewModel.weatherLabel(weather))
                    .font(.headline)
                    .lineLimit(1)
                Text(viewModel.formatMetrics(precipitation: weather.maxPrecipitation, cloudCover: weather.avgCloudCover))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.formatWindSpeed(weather.avgWindSpeed))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("不明")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("データなし")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("10日以内のみ")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Weather Symbol Visual

private struct WeatherSymbolVisual: View {
    let weather: DayWeatherSummary?

    var body: some View {
        Image(systemName: weather?.weatherIconName ?? "questionmark.circle")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(
                weather.map { WeatherPresentation.color(forWeatherCode: $0.representativeWeatherCode) }
                ?? .secondary
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
