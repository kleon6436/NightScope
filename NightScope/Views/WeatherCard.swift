import SwiftUI

struct NightWeatherCard: View {
    let weather: DayWeatherSummary?
    let isLoading: Bool
    let isForecastOutOfRange: Bool
    let isCoverageIncomplete: Bool
    let errorMessage: String?
    @ObservedObject var viewModel: NightWeatherCardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CardHeader(icon: AppIcons.Weather.cloud, iconColor: .cyan, title: "天気 (夜間)")
            HStack(alignment: .center, spacing: Spacing.sm) {
                weatherVisual
                weatherTextContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: CardVisual.metricVisualHeight, alignment: .leading)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            viewModel.accessibilityDescription(
                weather: weather,
                isLoading: isLoading,
                isForecastOutOfRange: isForecastOutOfRange,
                isCoverageIncomplete: isCoverageIncomplete,
                errorMessage: errorMessage
            )
        )
    }

    @ViewBuilder
    private var weatherVisual: some View {
        WeatherSymbolVisual(weather: weather, isLoading: isLoading)
            .frame(width: CardVisual.width, height: CardVisual.arcHeight)
            .summaryCardMetricVisualFrame()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var weatherTextContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let weather, !isCoverageIncomplete {
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
            } else if isCoverageIncomplete {
                Text(viewModel.partialCoverageTitle())
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.partialCoveragePrimaryText())
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.partialCoverageSecondaryText())
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if isLoading {
                Text(L10n.tr("取得中..."))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("最新データを取得しています")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("しばらくお待ちください")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let errorMessage {
                Text(viewModel.errorTitle())
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.errorPrimaryText(errorMessage))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.errorSecondaryText())
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(viewModel.unavailableTitle(isForecastOutOfRange: isForecastOutOfRange))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.unavailablePrimaryText(isForecastOutOfRange: isForecastOutOfRange))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(viewModel.unavailableSecondaryText(isForecastOutOfRange: isForecastOutOfRange))
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
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading && weather == nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: weather?.weatherIconName ?? "questionmark.circle")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        weather.map { WeatherPresentation.color(forWeatherCode: $0.representativeWeatherCode) }
                        ?? .secondary
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WeatherAttributionBadge

/// WeatherKit 利用規約に基づく帰属表示バッジ。
/// compact: カード内（小さめ、タップで法的情報ページへ）
/// full: 設定画面用（大きめ + 法的情報リンク）
struct WeatherAttributionBadge: View {
    enum Style { case compact, full }

    var style: Style = .compact

    @EnvironmentObject private var attributionService: WeatherAttributionService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let data = attributionService.attributionData {
                let logoURL = colorScheme == .dark ? data.logoDarkURL : data.logoLightURL
                switch style {
                case .compact:
                    Link(destination: data.legalPageURL) {
                        combinedMark(url: logoURL, height: 12)
                    }
                    .buttonStyle(.plain)
                case .full:
                    VStack(alignment: .leading, spacing: 4) {
                        combinedMark(url: logoURL, height: 12)
                        Link("法的情報・著作権", destination: data.legalPageURL)
                            .font(.caption2)
                    }
                }
            } else {
                Text("Apple Weather")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .task { await attributionService.loadIfNeeded() }
    }

    private func combinedMark(url: URL, height: CGFloat) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text("Apple Weather")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(height: height)
    }
}
